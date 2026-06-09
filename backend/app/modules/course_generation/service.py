"""Orchestration: outline -> lessons -> slides -> video, persisted with Job progress."""
from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.db import SessionLocal
from app.modules.course_generation import models, schemas
from app.modules.course_generation.generators import lesson as lesson_gen
from app.modules.course_generation.generators import outline as outline_gen
from app.modules.course_generation.generators import slides as slides_gen
from app.providers.llm import get_llm


def _set_progress(db: Session, job: models.Job, pct: int, step: str) -> None:
    job.progress = pct
    job.step = step
    db.commit()


def run_generation(job_id: int, req: schemas.GenerateRequest) -> None:
    """Background task: outline → lessons → enhanced slides."""
    db = SessionLocal()
    job = db.get(models.Job, job_id)
    try:
        job.status = models.JobStatus.running
        _set_progress(db, job, 5, "Generating outline")
        llm = get_llm()
        content = req.content_text

        outline = outline_gen.generate_outline(llm, content, req.mode, req.title_hint)

        course = models.Course(
            title=outline.title,
            description=outline.description,
            learning_objectives=outline.learning_objectives,
            mode=models.CourseMode(req.mode),
            languages=req.languages,
            status="generating",
        )
        db.add(course)
        db.flush()
        job.course_id = course.id

        total_lessons = sum(len(m.lessons) for m in outline.modules) or 1
        done = 0

        for m_i, m in enumerate(outline.modules):
            module = models.Module(
                course_id=course.id, order=m_i, title=m.title, objectives=m.objectives
            )
            db.add(module)
            db.flush()

            for l_i, ls in enumerate(m.lessons):
                lc = lesson_gen.generate_lesson_content(
                    llm, content, outline.title, m.title, ls.title, ls.learning_objectives
                )
                lesson = models.Lesson(
                    module_id=module.id,
                    order=l_i,
                    title=ls.title,
                    learning_objectives=ls.learning_objectives,
                    key_takeaways=lc.key_takeaways,
                    simplified_explanation=lc.simplified_explanation,
                    real_world_examples=lc.real_world_examples,
                    safety_scenarios=[s.model_dump() for s in lc.safety_scenarios],
                    summary=lc.summary,
                    narration_script=lc.narration_script,
                )
                db.add(lesson)
                db.flush()

                # Enhanced slides
                deck = slides_gen.generate_slide_deck(llm, content, ls.title, lc)
                for s_i, spec in enumerate(deck.slides):
                    db.add(models.Slide(
                        lesson_id=lesson.id, order=s_i, type=spec.type,
                        payload=spec.model_dump()
                    ))

                done += 1
                _set_progress(
                    db, job,
                    5 + int(90 * done / total_lessons),
                    f"Lesson: {ls.title}",
                )

        course.status = "ready"
        job.status = models.JobStatus.completed
        _set_progress(db, job, 100, "Completed")

    except Exception as e:
        db.rollback()
        job = db.get(models.Job, job_id)
        job.status = models.JobStatus.failed
        job.error = f"{type(e).__name__}: {e}"
        db.commit()
    finally:
        db.close()


def run_video_render(
    render_id: int,
    lesson_id: int,
    lang: str,
    style: str = "claude_native",
    course_type: str = "detailed",
    duration_minutes: int = 15,
    economy: str = "lean",
) -> None:
    """Background task: build a teaching video → MP4, routed by style.

    New style set (see style_prompts.STYLE_CATALOG):
      animated_scene     → HeyGen rich motion-graphics (paid)
      whiteboard_doodle  → HeyGen hand-drawn instructor (paid)
      claude_native      → free in-house whiteboard engine
      hybrid             → free Claude base + premium HeyGen scenes

    course_type: "quick" (one ~15-min video) or "detailed" (per-lesson, in depth).
    Legacy keys (whiteboard/modern/flatcolor/dark) still work.
    """
    from app.modules.course_generation.generators.animated_render import (
        generate_synced_video,
        generate_whiteboard_video,
    )
    from app.modules.course_generation.generators.heygen_render import (
        generate_heygen_video,
        generate_hybrid_video,
    )

    db = SessionLocal()
    render = db.get(models.VideoRender, render_id)
    try:
        render.status = models.JobStatus.running
        db.commit()

        lesson = db.get(models.Lesson, lesson_id)
        lc = schemas.LessonContent(
            key_takeaways=lesson.key_takeaways,
            simplified_explanation=lesson.simplified_explanation,
            real_world_examples=lesson.real_world_examples,
            safety_scenarios=[schemas.SafetyScenario(**s) for s in lesson.safety_scenarios],
            summary=lesson.summary,
            narration_script=lesson.narration_script,
        )

        if style in ("animated_scene", "whiteboard_doodle"):
            video_path = generate_heygen_video(
                lesson_id=lesson_id,
                lesson_title=lesson.title,
                lesson_content=lc,
                style=style,
                lang=lang,
                course_type=course_type,
                duration_minutes=duration_minutes,
                economy=economy,
            )
        elif style == "hybrid":
            video_path = generate_hybrid_video(
                lesson_id=lesson_id,
                lesson_title=lesson.title,
                lesson_content=lc,
                lang=lang,
                course_type=course_type,
                duration_minutes=duration_minutes,
            )
        elif style in ("claude_native", "whiteboard"):
            video_path = generate_whiteboard_video(
                lesson_id=lesson_id,
                lesson_title=lesson.title,
                lesson_content=lc,
                lang=lang,
            )
        else:  # legacy: modern / flatcolor / dark
            video_path = generate_synced_video(
                lesson_id=lesson_id,
                lesson_title=lesson.title,
                lesson_content=lc,
                lang=lang,
                style=style,
            )

        render.video_path = str(video_path)
        render.status = models.JobStatus.completed
        db.commit()

    except Exception as e:
        db.rollback()
        render = db.get(models.VideoRender, render_id)
        render.status = models.JobStatus.failed
        render.error = f"{type(e).__name__}: {e}"
        db.commit()
    finally:
        db.close()
