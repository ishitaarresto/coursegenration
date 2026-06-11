"""
api/routers/chat.py

POST  /api/v1/chat    Ask a question, get a grounded answer with source citations
"""

import asyncio

from fastapi import APIRouter, Depends, HTTPException

from api.config import settings
from api.dependencies import get_retrieval_pipeline, get_embedder, get_vector_store
from api.schemas import ChatRequest, ChatResponse, SourceInfo

router = APIRouter(prefix="/api/v1/chat", tags=["Chat / RAG"])

_SYSTEM_PROMPT = (
    "You are a helpful assistant for Arresto LMS. "
    "You answer questions based strictly on the document context provided. "
    "Always mention which source document your answer comes from. "
    "If the context is insufficient, say so clearly instead of guessing."
)


def _build_context(chunks: list[dict]) -> str:
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
        parts.append(
            f"[{i}] {meta.get('source_file', 'unknown')} ({loc}{heading})  "
            f"score: {c.get('score', 0):.2f}\n{c['text']}"
        )
    return "\n\n" + "-" * 60 + "\n\n".join(parts)


def _chunks_to_sources(chunks: list[dict]) -> list[SourceInfo]:
    sources = []
    for c in chunks:
        meta  = c.get("metadata", {})
        page  = meta.get("page_number",  -1)
        slide = meta.get("slide_number", -1)
        sources.append(SourceInfo(
            chunk_id=c["chunk_id"],
            source_file=meta.get("source_file", ""),
            score=round(c.get("score", 0), 4),
            section_heading=meta.get("section_heading") or None,
            page_number=page  if page  > 0 else None,
            slide_number=slide if slide > 0 else None,
            text_preview=c["text"][:300],
        ))
    return sources


def _generate_answer(question: str, chunks: list[dict], api_key: str) -> str:
    import anthropic
    client = anthropic.Anthropic(api_key=api_key)
    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        system=_SYSTEM_PROMPT,
        messages=[{
            "role": "user",
            "content": (
                f"Document context:\n{_build_context(chunks)}\n\n"
                f"Question: {question}\n\n"
                "Answer based on the context above. "
                "Cite the source document by name in your answer."
            ),
        }],
    )
    return response.content[0].text


@router.post("", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    retrieval_pipeline=Depends(get_retrieval_pipeline),
    embedder=Depends(get_embedder),
    vector_store=Depends(get_vector_store),
):
    """
    Ask a question about any document in the knowledge base.

    Uses the advanced retrieval pipeline (bge-m3 hybrid search + cross-encoder
    reranking) when available; falls back to direct vector search otherwise.
    """
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    try:
        if retrieval_pipeline is not None:
            result = await asyncio.to_thread(
                retrieval_pipeline.retrieve,
                request.question,
                request.source_file,
                [],
            )
            chunks = result.chunks
        else:
            q_vec = await asyncio.to_thread(embedder.embed_query, request.question)
            chunks = await asyncio.to_thread(
                vector_store.query, q_vec, 5, request.source_file, request.asset_type,
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

    try:
        answer = await asyncio.to_thread(
            _generate_answer, request.question, chunks, settings.anthropic_api_key,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Answer generation failed: {exc}")

    return ChatResponse(
        question=request.question,
        answer=answer,
        sources=sources,
        model_used="claude-sonnet-4-6",
    )
