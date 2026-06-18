"""
api/routers/questions.py

POST /api/v1/questions/generate   Generate MCQ knowledge-check questions from a lesson.
                                  Called by the lesson player to populate the
                                  InteractiveQuestionOverlay.
"""

import asyncio
import json
import re

from fastapi import APIRouter, HTTPException

from api.config import settings
from api.schemas import QuestionGenerationRequest, QuestionGenerationResponse, GeneratedQuestion

router = APIRouter(prefix="/api/v1/questions", tags=["Questions"])

_SYSTEM = (
    "You are an expert instructional designer for safety training. "
    "Generate a mix of multiple-choice and true/false questions that test genuine understanding. "
    "Avoid trivial or trick questions. Always return valid JSON, nothing else."
)

_QUESTION_SCHEMA = """
Return a JSON object with this exact structure (no markdown, no explanation, just JSON):
{
  "questions": [
    {
      "type": "multipleChoice",
      "prompt": "Question text here?",
      "options": ["Option A text", "Option B text", "Option C text", "Option D text"],
      "correct_index": 0
    },
    {
      "type": "trueFalse",
      "prompt": "Statement that is true or false?",
      "options": ["True", "False"],
      "correct_index": 0
    }
  ]
}
Rules:
- type is either "multipleChoice" or "trueFalse"
- multipleChoice must have exactly 4 options
- trueFalse must have exactly ["True", "False"] as options
- correct_index is 0-based (0 = first option)
"""


def _lookup_lesson(course_id: str, lesson_id: str) -> tuple[str, str] | None:
    """Returns (lesson_title, narration_script) or None."""
    try:
        m = re.match(r'm(\d+)l(\d+)', lesson_id)
        if not m:
            return None
        module_num = int(m.group(1))
        lesson_num = int(m.group(2))

        from api.db import SessionLocal
        from api.models.courses import CourseScriptRow

        db = SessionLocal()
        try:
            row = db.query(CourseScriptRow).filter(
                CourseScriptRow.script_id == course_id
            ).first()
            if not row:
                return None
            script = json.loads(row.course_script_json)
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


def _generate_questions(
    narration: str,
    lesson_title: str,
    count: int,
    timestamp_secs: int | None,
    api_key: str,
) -> list[GeneratedQuestion]:
    import anthropic

    timestamp_note = ""
    if timestamp_secs is not None:
        m, s = divmod(timestamp_secs, 60)
        timestamp_note = (
            f"\nThe learner is at {m}:{s:02d} — "
            f"focus questions on material covered up to this point."
        )

    # For 3 questions: 2 MCQ + 1 True/False. For other counts scale proportionally.
    tf_count  = max(1, count // 3)
    mcq_count = count - tf_count

    user_msg = (
        f"Lesson: {lesson_title}{timestamp_note}\n\n"
        f"Transcript:\n{narration[:8000]}\n\n"
        f"Generate exactly {count} questions from this lesson: "
        f"{mcq_count} multiple-choice (4 options each) and {tf_count} true/false.\n\n"
        f"{_QUESTION_SCHEMA}"
    )

    client = anthropic.Anthropic(api_key=api_key)
    resp = client.messages.create(
        model=settings.llm_model,
        max_tokens=2000,
        system=_SYSTEM,
        messages=[{"role": "user", "content": user_msg}],
    )
    raw = resp.content[0].text.strip()

    # Strip markdown code fences if present
    raw = re.sub(r'^```(?:json)?\s*', '', raw)
    raw = re.sub(r'\s*```$', '', raw)

    data = json.loads(raw)
    questions = []
    for q in data.get("questions", []):
        questions.append(GeneratedQuestion(
            type=q.get("type", "multipleChoice"),
            prompt=q["prompt"],
            options=q.get("options", []),
            correct_index=q.get("correct_index"),
        ))
    return questions


@router.post("/generate", response_model=QuestionGenerationResponse)
async def generate_questions(request: QuestionGenerationRequest):
    """
    Generate MCQ knowledge-check questions from a lesson's narration script.

    The lesson player calls this when `_showKCheck` triggers (e.g. at 25% playback).
    Returns questions in the format expected by `InteractiveQuestionOverlay`.
    """
    if not settings.anthropic_api_key:
        raise HTTPException(
            status_code=503,
            detail="ANTHROPIC_API_KEY not set — question generation unavailable.",
        )

    result = await asyncio.to_thread(
        _lookup_lesson, request.course_id, request.lesson_id
    )
    if not result:
        raise HTTPException(
            status_code=404,
            detail=f"Lesson '{request.lesson_id}' not found in course '{request.course_id}'.",
        )

    lesson_title, narration = result

    try:
        questions = await asyncio.to_thread(
            _generate_questions,
            narration,
            lesson_title,
            request.count,
            request.timestamp_secs,
            settings.anthropic_api_key,
        )
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=500, detail=f"LLM returned invalid JSON: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Question generation failed: {exc}")

    return QuestionGenerationResponse(lesson_title=lesson_title, questions=questions)
