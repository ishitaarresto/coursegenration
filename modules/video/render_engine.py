"""Video render engine — bridges LMS course data to the animated render pipeline.

Accepts lesson dicts from two course formats:

  Standard (module/lesson) courses
  ─────────────────────────────────
  course_script["modules"][m]["lessons"][l]  →  render_lesson()

  Custom (micro-course / blueprint) courses
  ──────────────────────────────────────────
  course_script["items"][i]  (type=="slide" or "closing_slide")  →  render_item()

Both paths:
  1. Convert the lesson/item dict to LessonContent + list[SlideSpec]
  2. Call generate_animated_video() → MP4
  3. (Optional) call the HeyGen pipeline for premium avatar videos

The narration is passed as-is to TTS — already in the correct language (Hindi,
English, etc.) — no auto-translation is performed.
"""
from __future__ import annotations

import asyncio
import re
import time
from pathlib import Path

from modules.video import schemas
from modules.video.job_store import VideoRenderJob, video_job_store

# ── Scene splitting ───────────────────────────────────────────────────────────

_SCENE_TARGET_WORDS = 150


def _split_into_scenes(narration: str) -> list[str]:
    """Split a long narration into ≤_SCENE_TARGET_WORDS-word scenes.

    Splits first at paragraph boundaries (\\n\\n), then at sentence boundaries
    (। . ! ?) for paragraphs that are themselves too long (common with
    AI-generated scripts that produce one big paragraph).
    """
    paragraphs = [p.strip() for p in narration.strip().split('\n\n') if p.strip()]
    if not paragraphs:
        return [narration.strip() or '']

    # Break oversized paragraphs into sentence-level units first
    units: list[str] = []
    for para in paragraphs:
        if len(para.split()) <= _SCENE_TARGET_WORDS:
            units.append(para)
        else:
            sentences = re.split(r'(?<=[।.!?])\s+', para.strip())
            current_sents: list[str] = []
            current_count = 0
            for sent in sentences:
                wc = len(sent.split())
                if current_count > 0 and current_count + wc > _SCENE_TARGET_WORDS:
                    units.append(' '.join(current_sents))
                    current_sents, current_count = [sent], wc
                else:
                    current_sents.append(sent)
                    current_count += wc
            if current_sents:
                units.append(' '.join(current_sents))

    # Group units into scenes
    scenes: list[str] = []
    current_parts: list[str] = []
    current_count = 0
    for unit in units:
        wc = len(unit.split())
        if current_count > 0 and current_count + wc > _SCENE_TARGET_WORDS:
            scenes.append('\n\n'.join(current_parts))
            current_parts, current_count = [unit], wc
        else:
            current_parts.append(unit)
            current_count += wc
    if current_parts:
        scenes.append('\n\n'.join(current_parts))

    return scenes or [narration]


split_into_scenes = _split_into_scenes


def count_lesson_scenes(lesson: dict) -> int:
    return len(_split_into_scenes(lesson.get('narration_script', '')))


# ── Adapters: LMS dict → LessonContent + SlideSpec ───────────────────────────

def _standard_lesson_to_content(
    lesson: dict,
) -> tuple[str, str, schemas.LessonContent, list[schemas.SlideSpec]]:
    """Convert a standard LMS lesson dict to (title, narration, LessonContent, slides)."""
    title    = lesson.get("lesson_title", "Lesson")
    narration = lesson.get("narration_script", "")
    slide     = lesson.get("slide_content", {})
    bullets   = slide.get("bullets", [])
    objectives = lesson.get("learning_objectives", [])

    lc = schemas.LessonContent(
        narration_script=narration,
        key_takeaways=bullets[:5],
        simplified_explanation=" ".join(objectives[:2]),
        real_world_examples=objectives[2:5],
        safety_scenarios=[],
        summary=slide.get("title", title),
    )

    slides: list[schemas.SlideSpec] = [
        schemas.SlideSpec(type="title", heading=slide.get("title", title), icon="book"),
    ]
    if bullets:
        slides.append(schemas.SlideSpec(
            type="content",
            heading=slide.get("title", title),
            bullets=bullets[:5],
        ))
    if lesson.get("key_terms"):
        slides.append(schemas.SlideSpec(
            type="summary",
            heading="Key Terms",
            bullets=[f"• {t}" for t in lesson["key_terms"][:5]],
        ))

    return title, narration, lc, slides


def _item_to_content(
    item: dict,
) -> tuple[str, str, schemas.LessonContent, list[schemas.SlideSpec]]:
    """Convert a custom course item dict to (title, narration, LessonContent, slides)."""
    title    = item.get("title", "Slide")
    narration = item.get("narration", "")
    bullets   = item.get("bullets", [])
    takeaway  = item.get("takeaway", "")

    lc = schemas.LessonContent(
        narration_script=narration,
        key_takeaways=bullets[:5],
        simplified_explanation="",
        real_world_examples=[],
        safety_scenarios=[],
        summary=takeaway or title,
    )

    slides: list[schemas.SlideSpec] = [
        schemas.SlideSpec(type="title",   heading=title,  icon="book"),
        schemas.SlideSpec(type="content", heading=title,  bullets=bullets[:5]),
    ]
    if takeaway:
        slides.append(schemas.SlideSpec(
            type="summary",
            heading="सार / Takeaway",
            bullets=[takeaway],
        ))

    return title, narration, lc, slides


# ── Core render call ─────────────────────────────────────────────────────────

_HEYGEN_STYLES = {"animated_scene", "whiteboard_doodle", "hybrid"}


def _do_render(
    job: VideoRenderJob,
    lesson_title: str,
    narration: str,
    lc: schemas.LessonContent,
    slides: list[schemas.SlideSpec],
) -> None:
    """Run the render pipeline and update the job in-place."""
    job.status = "processing"
    video_job_store.save()

    try:
        if job.style in _HEYGEN_STYLES:
            # ── HeyGen premium render ─────────────────────────────────────────
            from modules.video.generators.heygen_render import generate_heygen_video
            out_path = (
                Path("media") / "heygen" / job.render_id / f"{job.lang}.mp4"
            )
            # Map Sarvam speaker names to male/female preference for HeyGen prompt
            _v = (job.voice or "").lower()
            voice_pref = (
                "male" if _v in ("male", "rahul", "gokul", "m") else
                "female" if _v in ("female", "ritu", "kavitha", "priya", "kavya",
                                   "ishita", "pooja", "simran", "neha", "f") else
                "male"  # default to male narrator for safety training
            )
            mp4_path: Path = generate_heygen_video(
                lesson_id=job.render_id,
                lesson_title=lesson_title,
                lc=lc,
                style=job.style,
                lang=job.lang,
                out_path=out_path,
                voice_preference=voice_pref,
            )
        else:
            # ── Free animated render (default) ────────────────────────────────
            from modules.video.generators.animated_render import generate_animated_video
            from modules.video.generators.tts_router import active_engine

            job.tts_engine = active_engine(job.lang)
            video_job_store.save()
            mp4_path = generate_animated_video(
                lesson_id=job.render_id,
                lesson_title=lesson_title,
                lesson_content=lc,
                slides=slides,
                narration_script=narration,
                lang=job.lang,
                style=job.style,
                voice=job.voice or None,
            )

        job.video_path  = str(mp4_path.resolve())
        job.status      = "completed"
        job.finished_at = time.time()

        try:
            from api.notification_store import push as _notif
            _notif(
                "admin",
                "Video Ready",
                f'Lesson "{job.lesson_ref}" rendered successfully.',
                "🎬",
                "video_rendered",
            )
        except Exception:
            pass
    except Exception as exc:
        job.status      = "failed"
        job.error       = str(exc)
        job.finished_at = time.time()
    finally:
        video_job_store.save()


# ── Public entry points ───────────────────────────────────────────────────────

def render_lesson(
    job: VideoRenderJob,
    lesson: dict,
) -> None:
    """Render a lesson (or one scene of it) from a standard (module/lesson) course script."""
    title, narration, lc, slides = _standard_lesson_to_content(lesson)
    if job.scene_index is not None:
        scenes = _split_into_scenes(narration)
        if 0 <= job.scene_index < len(scenes):
            narration = scenes[job.scene_index]
            lc.narration_script = narration
        title = f"{title} — Part {job.scene_index + 1}"
    _do_render(job, title, narration, lc, slides)


def render_item(
    job: VideoRenderJob,
    item: dict,
) -> None:
    """Render a slide item from a custom (blueprint/micro-course) script."""
    title, narration, lc, slides = _item_to_content(item)
    _do_render(job, title, narration, lc, slides)


# ── Async wrappers (called from FastAPI BackgroundTasks) ──────────────────────

async def render_lesson_in_background(job: VideoRenderJob, lesson: dict) -> None:
    await asyncio.to_thread(render_lesson, job, lesson)


async def render_item_in_background(job: VideoRenderJob, item: dict) -> None:
    await asyncio.to_thread(render_item, job, item)
