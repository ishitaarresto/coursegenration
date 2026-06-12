"""Direct course importer — zero LLM calls.

Accepts the structured JSON produced by the content-ingestion pipeline
(the coworker's Module 1 output) and writes it straight to the DB.

Input shape (top-level fields used):
    course_title, course_description, target_audience, modules[]
      └─ module_number, module_title, module_description, lessons[]
           └─ lesson_number, lesson_title, duration_minutes,
              learning_objectives[], narration_script,
              slide_content{title, bullets}, key_terms[], visual_description

Everything the video renderer needs (narration_script, key_takeaways, slides)
is populated from the JSON directly — no Claude needed.
"""
from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from app.modules.course_generation import models


def import_course(payload: dict[str, Any], db: Session) -> models.Course:
    """Write the ingested course JSON to the DB and return the Course row."""

    # ── 1. Course ──────────────────────────────────────────────────────────
    course_script = payload.get("course_script") or payload  # handle both wrappers
    course = models.Course(
        title=course_script.get("course_title", "Imported Course"),
        description=course_script.get("course_description", ""),
        learning_objectives=[],
        mode=models.CourseMode.detailed,
        languages=["en"],
        status="ready",
    )
    db.add(course)
    db.flush()

    # ── 2. Modules + Lessons ───────────────────────────────────────────────
    for m_data in course_script.get("modules", []):
        module = models.Module(
            course_id=course.id,
            order=int(m_data.get("module_number", 1)) - 1,
            title=m_data.get("module_title", ""),
            objectives=[m_data.get("module_description", "")],
        )
        db.add(module)
        db.flush()

        for l_data in m_data.get("lessons", []):
            narration = l_data.get("narration_script", "")
            slide = l_data.get("slide_content", {})
            bullets: list[str] = slide.get("bullets", [])
            key_terms: list[str] = l_data.get("key_terms", [])
            visual_desc: str = l_data.get("visual_description", "")

            lesson = models.Lesson(
                module_id=module.id,
                order=int(l_data.get("lesson_number", 1)) - 1,
                title=l_data.get("lesson_title", ""),
                learning_objectives=l_data.get("learning_objectives", []),
                # key_takeaways → slide bullets (already great one-liners)
                key_takeaways=bullets,
                # simplified_explanation → visual description (great for scene planning)
                simplified_explanation=visual_desc,
                real_world_examples=[],
                safety_scenarios=[],
                summary=slide.get("speaker_notes", ""),
                narration_script=narration,
            )
            db.add(lesson)
            db.flush()

            # Slides: one title slide + one content slide per lesson
            db.add(models.Slide(
                lesson_id=lesson.id, order=0, type="title",
                payload={"type": "title", "title": l_data.get("lesson_title", ""),
                         "subtitle": m_data.get("module_title", "")},
            ))
            db.add(models.Slide(
                lesson_id=lesson.id, order=1, type="content",
                payload={
                    "type": "content",
                    "title": slide.get("title", l_data.get("lesson_title", "")),
                    "bullets": bullets,
                    "notes": slide.get("speaker_notes", ""),
                    "key_terms": key_terms,
                },
            ))

    db.commit()
    db.refresh(course)
    return course
