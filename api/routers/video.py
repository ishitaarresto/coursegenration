"""
api/routers/video.py

POST   /api/v1/video/render                       Trigger video render for a lesson or slide item
GET    /api/v1/video/renders/{render_id}           Poll render job status
GET    /api/v1/video/renders/{render_id}/download  Stream the rendered MP4
GET    /api/v1/video/scripts/{script_id}/renders   List all renders for a course script
GET    /api/v1/video/languages                     Supported languages + TTS engine per lang
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from api.course_library import library
from modules.video.job_store import video_job_store
from modules.video.render_engine import render_item_in_background, render_lesson_in_background

router = APIRouter(prefix="/api/v1/video", tags=["Video Rendering"])


# ── Request / response schemas ─────────────────────────────────────────────────

class VideoRenderRequest(BaseModel):
    script_id: str = Field(..., description="script_id from GET /api/v1/courses/library")

    # Standard (module/lesson) course — provide module_number + lesson_number
    module_number: int | None = Field(None, ge=1, description="Module number (1-based) for standard courses")
    lesson_number: int | None = Field(None, ge=1, description="Lesson number (1-based) for standard courses")

    # Custom (blueprint/micro-course) — provide item_index
    item_index: int | None = Field(None, ge=0, description="0-based index into items[] for custom courses")

    lang:  str = Field("en",      description='BCP-47 language code: "en", "hi", "ta", "te", …')
    style: str = Field("modern",  description='"modern" | "flatcolor" | "whiteboard"')


class VideoRenderResponse(BaseModel):
    render_id: str
    status:    str
    message:   str


class VideoRenderStatus(BaseModel):
    render_id:   str
    script_id:   str
    lesson_ref:  str
    lang:        str
    style:       str
    status:      str
    tts_engine:  str
    error:       str | None
    started_at:  float
    finished_at: float | None
    video_ready: bool


# ── Helpers ────────────────────────────────────────────────────────────────────

def _get_script_or_404(script_id: str) -> dict:
    record = library.get(script_id)
    if not record:
        raise HTTPException(404, f"Script '{script_id}' not found in library.")
    return record


def _job_to_status(job) -> VideoRenderStatus:
    return VideoRenderStatus(
        render_id=job.render_id,
        script_id=job.script_id,
        lesson_ref=job.lesson_ref,
        lang=job.lang,
        style=job.style,
        status=job.status,
        tts_engine=job.tts_engine,
        error=job.error,
        started_at=job.started_at,
        finished_at=job.finished_at,
        video_ready=(job.status == "completed" and bool(job.video_path)),
    )


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post("/render", response_model=VideoRenderResponse, status_code=202)
async def render_video(
    request: VideoRenderRequest,
    background_tasks: BackgroundTasks,
):
    """
    Trigger an async video render for one lesson or slide item.

    **Standard courses** — supply `module_number` + `lesson_number`.

    **Custom / blueprint courses** (Hindi micro-courses, etc.) — supply `item_index`
    (0-based position in the `items` array; only `type=slide` or `type=closing_slide`
    items are renderable — quiz items are skipped).

    Poll **GET /api/v1/video/renders/{render_id}** until `status == "completed"`,
    then download with **GET /api/v1/video/renders/{render_id}/download**.

    **TTS engine selection** (automatic via `TTS_PROVIDER` in .env):
    - `hi`, `ta`, `te`, `bn`, `gu`, `kn`, `ml`, `mr`, `pa`, `od` → Sarvam Bulbul-v3
      (requires `SARVAM_API_KEY`; falls back to edge-tts if key not set)
    - All other languages → edge-tts (free, no key required)
    """
    record      = _get_script_or_404(request.script_id)
    course      = record.get("course_script", {})
    lesson_ref  = ""
    lesson_data = None

    # ── Resolve the lesson/item ─────────────────────────────────────────────────
    if request.item_index is not None:
        # Custom course path
        items = course.get("items", [])
        if request.item_index >= len(items):
            raise HTTPException(
                400,
                f"item_index {request.item_index} is out of range "
                f"(course has {len(items)} items).",
            )
        item = items[request.item_index]
        if item.get("type") not in ("slide", "closing_slide"):
            raise HTTPException(
                400,
                f"item_index {request.item_index} is type '{item.get('type')}' — "
                "only 'slide' and 'closing_slide' items can be rendered.",
            )
        lesson_ref  = f"item_{request.item_index}"
        lesson_data = item

    elif request.module_number is not None and request.lesson_number is not None:
        # Standard module/lesson path
        modules = course.get("modules", [])
        mod = next(
            (m for m in modules if m.get("module_number") == request.module_number),
            None,
        )
        if mod is None:
            raise HTTPException(404, f"Module {request.module_number} not found.")
        lessons = mod.get("lessons", [])
        les = next(
            (l for l in lessons if l.get("lesson_number") == request.lesson_number),
            None,
        )
        if les is None:
            raise HTTPException(
                404,
                f"Lesson {request.lesson_number} not found in module {request.module_number}.",
            )
        lesson_ref  = f"module_{request.module_number}_lesson_{request.lesson_number}"
        lesson_data = les

    else:
        raise HTTPException(
            400,
            "Provide either (module_number + lesson_number) for standard courses "
            "or item_index for custom/blueprint courses.",
        )

    # ── Create job + queue background task ──────────────────────────────────────
    job = video_job_store.create(
        script_id=request.script_id,
        lesson_ref=lesson_ref,
        lang=request.lang,
        style=request.style,
    )

    if request.item_index is not None:
        background_tasks.add_task(render_item_in_background, job, lesson_data)
    else:
        background_tasks.add_task(render_lesson_in_background, job, lesson_data)

    return VideoRenderResponse(
        render_id=job.render_id,
        status="processing",
        message=(
            f"Video render started for '{lesson_ref}' "
            f"(lang={request.lang}, style={request.style}). "
            f"Poll /api/v1/video/renders/{job.render_id} to track progress."
        ),
    )


@router.get("/renders/{render_id}", response_model=VideoRenderStatus)
def get_render_status(render_id: str):
    """Poll the status of a video render job."""
    job = video_job_store.get(render_id)
    if not job:
        raise HTTPException(404, f"Render job '{render_id}' not found.")
    return _job_to_status(job)


@router.get("/renders/{render_id}/download")
def download_video(render_id: str):
    """
    Download the rendered MP4 when `status == "completed"`.

    Returns a streaming MP4 response suitable for browser `<video>` playback
    or saving to disk.
    """
    job = video_job_store.get(render_id)
    if not job:
        raise HTTPException(404, f"Render job '{render_id}' not found.")
    if job.status != "completed":
        raise HTTPException(
            409,
            f"Video is not ready yet (status={job.status}). "
            "Poll /renders/{render_id} and retry when status=='completed'.",
        )
    if not job.video_path or not Path(job.video_path).exists():
        raise HTTPException(500, "Video file not found on disk.")

    filename = f"{job.lesson_ref}_{job.lang}.mp4"
    return FileResponse(
        path=job.video_path,
        media_type="video/mp4",
        filename=filename,
    )


@router.get("/scripts/{script_id}/renders")
def list_script_renders(script_id: str):
    """List all render jobs for a course script."""
    _get_script_or_404(script_id)   # validate script exists
    jobs = video_job_store.list_for_script(script_id)
    return {
        "script_id": script_id,
        "renders":   [_job_to_status(j) for j in jobs],
        "total":     len(jobs),
    }


@router.get("/languages")
def list_languages():
    """
    Return all supported languages with their TTS engine.

    Returns a plain list (not wrapped in an object) so the Flutter frontend
    can cast it directly: `data as List`.
    `engine` reflects the *currently configured* provider (respects TTS_PROVIDER
    and whether SARVAM_API_KEY is set).
    """
    from modules.video.generators.tts import SUPPORTED_LANGUAGES
    from modules.video.generators.tts_router import active_engine

    return [
        {"lang": lang, "engine": active_engine(lang)}
        for lang in SUPPORTED_LANGUAGES
    ]
