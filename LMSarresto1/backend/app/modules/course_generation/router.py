"""REST endpoints for Course Generation module."""
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import FileResponse, HTMLResponse
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.modules.course_generation import models, schemas, service
from app.modules.course_generation.generators.slides import render_reveal_html
from app.modules.course_generation.generators.tts import SUPPORTED_LANGUAGES

router = APIRouter(prefix="/api", tags=["course-generation"])

# ── Course generation ──────────────────────────────────────────
@router.post("/courses/generate", response_model=schemas.JobOut)
def generate_course(
    req: schemas.GenerateRequest, background: BackgroundTasks, db: Session = Depends(get_db)
):
    job = models.Job(status=models.JobStatus.pending, step="queued")
    db.add(job)
    db.commit()
    db.refresh(job)
    background.add_task(service.run_generation, job.id, req)
    return job


@router.get("/jobs/{job_id}", response_model=schemas.JobOut)
def get_job(job_id: int, db: Session = Depends(get_db)):
    job = db.get(models.Job, job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return job


@router.post("/courses/import")
def import_course(
    payload: dict,
    db: Session = Depends(get_db),
):
    """Import a pre-built course JSON directly — NO LLM calls, instant.

    Accepts the output of the content-ingestion pipeline (Module 1).
    Returns {course_id, title, total_lessons} immediately.
    """
    from app.modules.course_generation.importer import import_course as _import

    try:
        course = _import(payload, db)
        total = sum(len(m.lessons) for m in course.modules)
        return {
            "course_id": course.id,
            "title": course.title,
            "total_lessons": total,
            "status": "ready",
            "message": f"Imported {total} lessons instantly — no generation needed.",
        }
    except Exception as e:
        raise HTTPException(400, f"Import failed: {type(e).__name__}: {e}")


@router.get("/courses/{course_id}", response_model=schemas.CourseOut)
def get_course(course_id: int, db: Session = Depends(get_db)):
    course = db.get(models.Course, course_id)
    if not course:
        raise HTTPException(404, "Course not found")
    return course


# ── Slides ─────────────────────────────────────────────────────
@router.get(
    "/courses/{course_id}/lessons/{lesson_id}/slides",
    response_class=HTMLResponse,
)
def get_lesson_slides(course_id: int, lesson_id: int, db: Session = Depends(get_db)):
    lesson = db.get(models.Lesson, lesson_id)
    if not lesson:
        raise HTTPException(404, "Lesson not found")
    specs = [schemas.SlideSpec.model_validate(s.payload) for s in lesson.slides]
    return HTMLResponse(render_reveal_html(lesson.title, specs))


# ── Video generation ───────────────────────────────────────────
@router.post("/courses/{course_id}/lessons/{lesson_id}/render")
def render_video(
    course_id: int,
    lesson_id: int,
    background: BackgroundTasks,
    lang: str = "en",
    style: str = "claude_native",
    course_type: str = "detailed",
    duration_minutes: int = 15,
    economy: str = "lean",
    db: Session = Depends(get_db),
):
    """Trigger animated video generation for a lesson.

    style: animated_scene | whiteboard_doodle | claude_native | hybrid (+legacy keys)
    course_type: quick (one ~15-min video) | detailed (per-lesson, in depth)
    """
    lesson = db.get(models.Lesson, lesson_id)
    if not lesson:
        raise HTTPException(404, "Lesson not found")
    if lang not in SUPPORTED_LANGUAGES:
        raise HTTPException(400, f"Unsupported language. Supported: {SUPPORTED_LANGUAGES}")

    # Reuse the render record per (lesson, lang); always re-render so the
    # learner can switch style/language and get a fresh video.
    render = (
        db.query(models.VideoRender)
        .filter_by(lesson_id=lesson_id, lang=lang)
        .first()
    )
    if not render:
        render = models.VideoRender(lesson_id=lesson_id, lang=lang)
        db.add(render)
    render.status = models.JobStatus.pending
    render.error = None
    db.commit()
    db.refresh(render)

    background.add_task(
        service.run_video_render,
        render.id, lesson_id, lang, style, course_type, duration_minutes, economy,
    )
    return {
        "render_id": render.id, "status": "started",
        "lang": lang, "style": style, "course_type": course_type, "economy": economy,
    }


@router.get("/courses/{course_id}/lessons/{lesson_id}/cost")
def estimate_render_cost(
    course_id: int, lesson_id: int, economy: str = "lean", db: Session = Depends(get_db)
):
    """FREE preview: how many HeyGen credits this lesson will cost, and current balance.

    Spends NOTHING — read-only. Lets the UI show cost before the user commits.
    """
    from app.modules.course_generation.generators import credit_economy
    from app.providers.video import heygen_provider

    lesson = db.get(models.Lesson, lesson_id)
    if not lesson:
        raise HTTPException(404, "Lesson not found")
    narration = lesson.narration_script or lesson.simplified_explanation or lesson.title or ""
    plan = credit_economy.plan(narration, economy)
    balance = heygen_provider.remaining_credits()
    return {
        **plan,
        "credits_remaining": balance,
        "affordable": (balance is None) or (balance >= plan["estimated_cost"]),
        "presets": list(credit_economy.ECONOMY_PRESETS.keys()),
    }


@router.get("/renders/{render_id}/status")
def render_status(render_id: int, db: Session = Depends(get_db)):
    r = db.get(models.VideoRender, render_id)
    if not r:
        raise HTTPException(404, "Render not found")
    return {"render_id": r.id, "status": r.status, "lang": r.lang, "error": r.error}


@router.get("/courses/{course_id}/lessons/{lesson_id}/video")
def get_lesson_video(
    course_id: int, lesson_id: int, lang: str = "en", db: Session = Depends(get_db)
):
    """Stream the MP4 video for a lesson."""
    render = (
        db.query(models.VideoRender)
        .filter_by(lesson_id=lesson_id, lang=lang, status=models.JobStatus.completed)
        .first()
    )
    if not render or not render.video_path:
        raise HTTPException(404, "Video not ready. POST to /render first.")
    path = Path(render.video_path)
    if not path.exists():
        raise HTTPException(404, "Video file missing on disk.")
    return FileResponse(str(path), media_type="video/mp4")


@router.get("/languages")
def list_languages():
    """List supported TTS languages with which engine handles each."""
    from app.modules.course_generation.generators.tts_router import active_engine
    from app.providers.video import heygen_provider

    langs = []
    for code in SUPPORTED_LANGUAGES:
        engine = active_engine(code)
        langs.append({"code": code, "engine": engine})
    return {
        "languages": SUPPORTED_LANGUAGES,
        "details": langs,
        "sarvam_ready": bool(__import__("app.core.config", fromlist=["settings"]).settings.sarvam_api_key.strip()),
        "heygen_ready": heygen_provider.is_configured(),
    }


@router.get("/styles")
def list_styles():
    """Rich style catalog for the pre-generation picker (label, tagline, engine, cost)."""
    from app.modules.course_generation.generators import style_prompts
    from app.providers.video import heygen_provider

    heygen_ready = heygen_provider.is_configured()
    styles = []
    for s in style_prompts.STYLE_CATALOG:
        styles.append({
            "key": s.key,
            "label": s.label,
            "tagline": s.tagline,
            "engine": s.engine,
            "paid": s.paid,
            "best_for": s.best_for,
            "cost_15min_inr": s.sample_cost_15min_inr,
            # A paid style is selectable only once the HeyGen key is configured.
            "available": (not s.paid) or heygen_ready,
        })
    return {
        "styles": styles,
        "course_types": [
            {"key": "quick", "label": "⚡ Quick Overview",
             "tagline": "One continuous ~15-min video of the whole topic."},
            {"key": "detailed", "label": "📚 Detailed Lessons",
             "tagline": "One in-depth video per lesson in the script."},
        ],
        "heygen_ready": heygen_ready,
        # Legacy keys kept for backward compatibility.
        "legacy_styles": ["whiteboard", "modern", "flatcolor", "dark"],
    }
