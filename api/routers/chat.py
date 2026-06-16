"""
api/routers/chat.py

POST  /api/v1/chat    Ask a question, get a grounded answer with source citations.
                      When called from the in-lesson AI companion, pass lesson_id,
                      course_id, timestamp_secs, and transcript_snippet for
                      context-aware answers about the current lesson.
                      Pass history (last N turns) for conversational follow-ups.
"""

import asyncio
import re

from fastapi import APIRouter, Depends, HTTPException

from api.config import settings
from api.dependencies import get_retrieval_pipeline, get_embedder, get_vector_store
from api.schemas import ChatRequest, ChatResponse, SourceInfo

router = APIRouter(prefix="/api/v1/chat", tags=["Chat / RAG"])

# ── Intent patterns — require explicit summarise/quiz/explain-section phrasing ──
# These are intentionally narrow to avoid false positives like "what is a summary?"
_RE_SUMMARIZE = re.compile(
    r'\b(summarize|summarise|sum\s+this\s+up|give\s+(me\s+)?a\s*(quick\s+)?recap|'
    r'summarize\s+(this\s+)?lesson|recap\s+(this\s+)?lesson|'
    r'what\s+did\s+(this\s+|the\s+)?lesson\s+(cover|discuss|explain|teach))\b',
    re.I,
)
_RE_QUIZ = re.compile(
    r'\b(quiz\s+me|test\s+me|generate\s+(quiz|practice|test)\s+questions?|'
    r'create\s+(some\s+)?questions?|make\s+(some\s+)?questions?|'
    r'knowledge\s+check|give\s+me\s+(a\s+)?quiz)\b',
    re.I,
)
_RE_EXPLAIN_SECTION = re.compile(
    r'\b(explain\s+(the\s+)?(current|this)\s+(section|part|segment|topic)|'
    r'what\s+(is|was|are)\s+(just|being|currently)\s+(covered|said|taught|explained|discussed)|'
    r'what.*(just|happening|said)\s+in\s+(the\s+)?lesson|'
    r'current\s+(part|section|segment))\b',
    re.I,
)

# ── System prompts ─────────────────────────────────────────────────────────────
_SYSTEM_BASE = (
    "You are Arresto AI, the expert safety training assistant for Arresto LMS. "
    "Your answers must be thorough, precise, and grounded in the provided context. "
    "Use markdown formatting: **bold** for key terms and safety-critical points, "
    "numbered lists for step-by-step procedures, bullet lists for multiple related points. "
    "For safety-critical topics (LOTO, arc flash, fall protection, PPE, electrical safety, "
    "confined space, hazmat), be especially complete and accurate — "
    "incomplete safety guidance can cause harm."
)

_SYSTEM_WITH_DOCS = _SYSTEM_BASE + (
    "\n\nYou answer using the retrieved document context provided. Rules:\n"
    "- Base every factual claim on specific content from the retrieved chunks.\n"
    "- Always cite the source document by name and page/slide inline (e.g. 'According to arc_flash_safety.pdf, page 4...').\n"
    "- If multiple chunks contain relevant information, synthesize them into one complete answer.\n"
    "- If the context does not contain enough information, say so clearly — do not guess.\n"
    "- For follow-up questions, use both the document context AND the conversation history above."
)

_SYSTEM_LESSON = _SYSTEM_BASE + (
    "\n\nThe learner is currently watching a lesson. "
    "Use the lesson transcript as your primary source. "
    "Be specific — quote or paraphrase directly what the lesson says. "
    "If the question relates to knowledge base documents, incorporate that as well."
)


def _lesson_context_block(transcript: str, lesson_title: str, timestamp_secs: int | None) -> str:
    lines = [f"LESSON TRANSCRIPT — {lesson_title}:", transcript[:12000]]
    if timestamp_secs is not None:
        m, s = divmod(timestamp_secs, 60)
        lines.append(f"\n(Learner is currently at {m}:{s:02d} in this lesson)")
    return "\n".join(lines)


def _build_doc_context(chunks: list[dict]) -> str:
    parts = []
    for i, c in enumerate(chunks, 1):
        meta  = c.get("metadata", {})
        page  = meta.get("page_number",  -1)
        slide = meta.get("slide_number", -1)
        loc = (
            f"page {page}"   if page  > 0 else
            f"slide {slide}" if slide > 0 else
            "document body"
        )
        heading = f" > {meta['section_heading']}" if meta.get("section_heading") else ""
        rerank  = c.get("rerank_score")
        score_str = f"rerank: {rerank:.3f}" if rerank is not None else f"score: {c.get('score', 0):.3f}"
        parts.append(
            f"[{i}] {meta.get('source_file', 'unknown')} ({loc}{heading})  "
            f"{score_str}\n{c['text']}"
        )
    return "\n\n" + ("-" * 60 + "\n\n").join(parts)


def _chunks_to_sources(chunks: list[dict]) -> list[SourceInfo]:
    sources = []
    for c in chunks:
        meta  = c.get("metadata", {})
        page  = meta.get("page_number",  -1)
        slide = meta.get("slide_number", -1)
        sources.append(SourceInfo(
            chunk_id=c["chunk_id"],
            source_file=meta.get("source_file", ""),
            score=round(c.get("rerank_score") or c.get("score", 0), 4),
            section_heading=meta.get("section_heading") or None,
            page_number=page  if page  > 0 else None,
            slide_number=slide if slide > 0 else None,
            text_preview=c["text"][:300],
        ))
    return sources


def _build_messages(user_content: str, history: list[dict]) -> list[dict]:
    """Build Anthropic messages list: history turns + current user message."""
    messages = []
    for h in history:
        role = h.get("role", "user")
        text = h.get("text", "")
        if role in ("user", "assistant") and text:
            messages.append({"role": role, "content": text})
    messages.append({"role": "user", "content": user_content})
    return messages


def _call_llm(system: str, messages: list[dict], api_key: str, max_tokens: int = 1500) -> str:
    import anthropic
    client = anthropic.Anthropic(api_key=api_key)
    response = client.messages.create(
        model=settings.llm_model,
        max_tokens=max_tokens,
        system=system,
        messages=messages,
    )
    return response.content[0].text


def _lookup_lesson_transcript(course_id: str, lesson_id: str) -> tuple[str, str] | None:
    """
    Look up lesson narration script from the DB.
    Returns (lesson_title, narration_script) or None if not found.
    lesson_id format: 'm{moduleNum}l{lessonNum}'
    """
    try:
        import json as _json
        from api.db import SessionLocal
        from api.models.courses import CourseScriptRow

        m = re.match(r'm(\d+)l(\d+)', lesson_id)
        if not m:
            return None
        module_num = int(m.group(1))
        lesson_num = int(m.group(2))

        db = SessionLocal()
        try:
            row = db.query(CourseScriptRow).filter(
                CourseScriptRow.script_id == course_id
            ).first()
            if not row:
                return None
            script = _json.loads(row.course_script_json)
            for mod in script.get("modules", []):
                if mod.get("module_number") == module_num:
                    for les in mod.get("lessons", []):
                        if les.get("lesson_number") == lesson_num:
                            title     = les.get("lesson_title", "")
                            narration = les.get("narration_script", "")
                            return (title, narration) if narration else None
        finally:
            db.close()
    except Exception:
        pass
    return None


def _looks_like_uuid(s: str) -> bool:
    return bool(re.match(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', s, re.I
    ))


@router.post("", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    retrieval_pipeline=Depends(get_retrieval_pipeline),
    embedder=Depends(get_embedder),
    vector_store=Depends(get_vector_store),
):
    """
    Ask a question about any document in the knowledge base.

    When called from the in-lesson AI companion, pass lesson_id, course_id,
    timestamp_secs, and transcript_snippet for context-aware answers.
    Pass history (last 6 turns) for multi-turn conversations.

    Intent-based shortcuts (only when transcript is available AND exact phrasing matches):
    - "Summarize this lesson" → summarize the full lesson transcript
    - "Quiz me on this lesson" → produce MCQ questions from the transcript
    - "Explain the current section" → explain the transcript near the given timestamp
    """
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    # ── Resolve lesson transcript ───────────────────────────────────────────────
    transcript   = request.transcript_snippet or ""
    lesson_title = ""

    if not transcript and request.course_id and request.lesson_id:
        result = await asyncio.to_thread(
            _lookup_lesson_transcript, request.course_id, request.lesson_id
        )
        if result:
            lesson_title, transcript = result

    has_lesson_ctx = bool(transcript)

    # ── Intent shortcuts (only for explicit lesson-level requests) ─────────────
    if has_lesson_ctx and settings.anthropic_api_key:
        q = request.question

        if _RE_SUMMARIZE.search(q):
            user_msg = (
                f"{_lesson_context_block(transcript, lesson_title, request.timestamp_secs)}\n\n"
                "Please provide a clear, structured summary of this lesson. "
                "Use bullet points for the key points and highlight any safety-critical information."
            )
            answer = await asyncio.to_thread(
                _call_llm, _SYSTEM_LESSON,
                _build_messages(user_msg, request.history),
                settings.anthropic_api_key, 1500,
            )
            return ChatResponse(
                question=request.question, answer=answer,
                sources=[], model_used=settings.llm_model,
            )

        if _RE_QUIZ.search(q):
            user_msg = (
                f"{_lesson_context_block(transcript, lesson_title, request.timestamp_secs)}\n\n"
                "Generate 3 multiple-choice questions to test understanding of this lesson. "
                "For each question provide:\n"
                "- The question\n"
                "- Four options (A, B, C, D)\n"
                "- The correct answer with a brief explanation\n\n"
                "Focus on safety-critical content. Format each question clearly, separated by a blank line."
            )
            answer = await asyncio.to_thread(
                _call_llm, _SYSTEM_LESSON,
                _build_messages(user_msg, request.history),
                settings.anthropic_api_key, 2000,
            )
            return ChatResponse(
                question=request.question, answer=answer,
                sources=[], model_used=settings.llm_model,
            )

        if _RE_EXPLAIN_SECTION.search(q) and request.timestamp_secs is not None:
            user_msg = (
                f"{_lesson_context_block(transcript, lesson_title, request.timestamp_secs)}\n\n"
                f'The learner asks: "{q}"\n\n'
                "Explain what is being covered at this point in the lesson in detail. "
                "Quote or closely paraphrase the transcript content near the current timestamp."
            )
            answer = await asyncio.to_thread(
                _call_llm, _SYSTEM_LESSON,
                _build_messages(user_msg, request.history),
                settings.anthropic_api_key, 1500,
            )
            return ChatResponse(
                question=request.question, answer=answer,
                sources=[], model_used=settings.llm_model,
            )

    # ── Standard RAG path ──────────────────────────────────────────────────────
    source_file = request.source_file
    if not source_file and request.course_id and not _looks_like_uuid(request.course_id):
        source_file = request.course_id

    # Format history for the retrieval pipeline's contextual rewriter
    pipeline_history = [
        {"role": h.get("role", "user"), "text": h.get("text", "")}
        for h in request.history
        if h.get("text")
    ]

    try:
        if retrieval_pipeline is not None:
            result = await asyncio.to_thread(
                retrieval_pipeline.retrieve,
                request.question,
                source_file,
                pipeline_history,
            )
            chunks = result.chunks
        else:
            q_vec = await asyncio.to_thread(embedder.embed_query, request.question)
            chunks = await asyncio.to_thread(
                vector_store.query, q_vec, request.n_chunks, source_file, request.asset_type,
            )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Retrieval failed: {exc}")

    sources = _chunks_to_sources(chunks)

    if not settings.anthropic_api_key:
        return ChatResponse(
            question=request.question,
            answer=(
                "[No LLM] Set ANTHROPIC_API_KEY to enable answer generation. "
                "Retrieved chunks are shown in sources."
            ),
            sources=sources,
            model_used=None,
        )

    # Build user content — inject lesson context on top of RAG chunks when available
    if has_lesson_ctx and chunks:
        user_content = (
            f"{_lesson_context_block(transcript, lesson_title, request.timestamp_secs)}\n\n"
            f"Additional document context:\n{_build_doc_context(chunks)}\n\n"
            f"Question: {request.question}\n\n"
            "Answer using both the lesson transcript and document context above. "
            "Cite specific sources by name."
        )
        system = _SYSTEM_LESSON
    elif has_lesson_ctx:
        user_content = (
            f"{_lesson_context_block(transcript, lesson_title, request.timestamp_secs)}\n\n"
            f"Question: {request.question}\n\n"
            "Answer based on the lesson transcript above."
        )
        system = _SYSTEM_LESSON
    else:
        if chunks:
            user_content = (
                f"Document context:\n{_build_doc_context(chunks)}\n\n"
                f"Question: {request.question}\n\n"
                "Answer based on the context above. "
                "Cite the source document and page/slide in your answer."
            )
        else:
            user_content = (
                f"Question: {request.question}\n\n"
                "No relevant documents were found in the knowledge base for this question. "
                "Answer based on general safety training knowledge, and note that this answer "
                "is not sourced from the uploaded documents."
            )
        system = _SYSTEM_WITH_DOCS

    messages = _build_messages(user_content, request.history)

    try:
        answer = await asyncio.to_thread(
            _call_llm, system, messages, settings.anthropic_api_key
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Answer generation failed: {exc}")

    return ChatResponse(
        question=request.question,
        answer=answer,
        sources=sources,
        model_used=settings.llm_model,
    )
