"""
api/routers/video.py

POST   /api/v1/video/render                       Trigger video render for a lesson or slide item
GET    /api/v1/video/renders/{render_id}           Poll render job status
GET    /api/v1/video/renders/{render_id}/download  Stream the rendered MP4
GET    /api/v1/video/scripts/{script_id}/renders   List all renders for a course script
GET    /api/v1/video/languages                     Supported languages + TTS engine per lang
"""

from __future__ import annotations

import re
from pathlib import Path

import asyncio

from fastapi import APIRouter, BackgroundTasks, HTTPException, Request
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import BaseModel, Field

from api.config import settings
from api.course_library import library
from modules.video.job_store import video_job_store
from modules.video.render_engine import (
    count_lesson_scenes,
    render_item_in_background,
    render_lesson_in_background,
)

# Styles that require a HeyGen API key — must match render_engine._HEYGEN_STYLES
_HEYGEN_STYLES = frozenset({"animated_scene", "whiteboard_doodle", "hybrid"})

# Map human-readable language names (stored in course_scripts.language) to BCP-47 codes.
# Used to auto-select the correct TTS voice when the frontend sends the default lang=en.
_LANG_NAME_TO_CODE: dict[str, str] = {
    "english":    "en",
    "hindi":      "hi",
    "tamil":      "ta",
    "telugu":     "te",
    "bengali":    "bn",
    "gujarati":   "gu",
    "kannada":    "kn",
    "malayalam":  "ml",
    "marathi":    "mr",
    "punjabi":    "pa",
    "odia":       "od",
    "oriya":      "od",
    "urdu":       "ur",
}


def _resolve_lang(requested_lang: str, record: dict) -> str:
    """Return the correct BCP-47 lang code for a render job.

    If the caller sent the default 'en' but the stored course language is
    different (e.g. 'Hindi'), return the proper code ('hi') so TTS selects
    the right engine and voice automatically.
    """
    if requested_lang != "en":
        return requested_lang          # caller was explicit — respect it
    stored = (record.get("language") or "").strip().lower()
    return _LANG_NAME_TO_CODE.get(stored, requested_lang)

router = APIRouter(prefix="/api/v1/video", tags=["Video Rendering"])


# ── Request / response schemas ─────────────────────────────────────────────────

class VideoRenderRequest(BaseModel):
    script_id: str = Field(..., description="script_id from GET /api/v1/courses/library")

    # Standard (module/lesson) course — provide module_number + lesson_number
    module_number: int | None = Field(None, ge=1, description="Module number (1-based) for standard courses")
    lesson_number: int | None = Field(None, ge=1, description="Lesson number (1-based) for standard courses")

    # Custom (blueprint/micro-course) — provide item_index
    item_index: int | None = Field(None, ge=0, description="0-based index into items[] for custom courses")

    lang:        str      = Field("en",  description='BCP-47 language code: "en", "hi", "ta", "te", …')
    style:       str      = Field("modern", description='"modern" | "flatcolor" | "whiteboard"')
    voice:       str      = Field("",   description='Sarvam speaker name override: "ritu", "rahul", "kavitha", … (empty = lang default)')
    scene_index: int | None = Field(None, ge=0, description="Scene index (0-based) within the lesson narration. Omit to render all scenes.")


class VideoRenderResponse(BaseModel):
    render_id:      str         # first (or only) job render_id
    render_ids:     list[str]   # all jobs created — one per scene when scene_index omitted
    status:         str
    message:        str
    scenes_created: int = 1


class VideoRenderStatus(BaseModel):
    render_id:   str
    script_id:   str
    lesson_ref:  str
    scene_index: int | None
    lang:        str
    style:       str
    status:      str
    tts_engine:  str
    voice:       str
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
        scene_index=job.scene_index,
        lang=job.lang,
        style=job.style,
        status=job.status,
        tts_engine=job.tts_engine,
        voice=job.voice or "",
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

    # ── Validate HeyGen key before accepting the job ────────────────────────────
    if request.style in _HEYGEN_STYLES and not settings.heygen_api_key:
        raise HTTPException(
            400,
            f"Style '{request.style}' requires a HeyGen API key. "
            "Set HEYGEN_API_KEY in your .env file, or choose a free style: "
            "modern, flatcolor, whiteboard.",
        )

    # Auto-resolve language: if caller sent default 'en' but the course was
    # generated in Hindi/Tamil/etc., switch to the correct BCP-47 code so
    # TTS picks the right voice.
    resolved_lang = _resolve_lang(request.lang, record)

    # ── Create job(s) + queue background tasks ──────────────────────────────────
    if request.item_index is not None:
        # Custom course: always a single item, no scene splitting
        job = video_job_store.create(
            script_id=request.script_id,
            lesson_ref=lesson_ref,
            lang=resolved_lang,
            style=request.style,
            voice=request.voice,
        )
        background_tasks.add_task(render_item_in_background, job, lesson_data)
        created_jobs = [job]
    else:
        # Standard lesson: create one job per scene (or one job for a specific scene)
        if request.scene_index is not None:
            scene_indices = [request.scene_index]
        else:
            n_scenes = count_lesson_scenes(lesson_data)
            scene_indices = list(range(n_scenes))

        created_jobs = []
        for si in scene_indices:
            job = video_job_store.create(
                script_id=request.script_id,
                lesson_ref=lesson_ref,
                lang=resolved_lang,
                style=request.style,
                voice=request.voice,
                scene_index=si,
            )
            background_tasks.add_task(render_lesson_in_background, job, lesson_data)
            created_jobs.append(job)

    first_id = created_jobs[0].render_id
    return VideoRenderResponse(
        render_id=first_id,
        render_ids=[j.render_id for j in created_jobs],
        status="processing",
        message=(
            f"Started {len(created_jobs)} scene job(s) for '{lesson_ref}' "
            f"(lang={resolved_lang}, style={request.style}). "
            f"Poll /api/v1/video/renders/{first_id} to track progress."
        ),
        scenes_created=len(created_jobs),
    )


@router.post("/generate-all/{script_id}", status_code=202)
async def generate_all_videos(
    script_id: str,
    background_tasks: BackgroundTasks,
    style: str = "modern",
    lang:  str = "en",
    voice: str = "",
):
    """
    Trigger video renders for every lesson in a course in one call.

    Creates one background render job per lesson (or per slide item for
    custom courses) and returns immediately.  Poll individual job IDs via
    GET /api/v1/video/renders/{render_id}.

    Lessons that already have a completed render for the same lang are
    skipped automatically, so this endpoint is safe to call multiple times
    to resume a partially-generated course.

    Style defaults to `modern` (free animated renderer).
    Pass style=animated_scene to use HeyGen (requires HEYGEN_API_KEY in .env).
    """
    if style in _HEYGEN_STYLES and not settings.heygen_api_key:
        raise HTTPException(
            400,
            f"Style '{style}' requires HEYGEN_API_KEY in .env. "
            "Set it or pass style=modern for the free renderer.",
        )

    record = _get_script_or_404(script_id)
    course = record.get("course_script", {})

    # Auto-resolve language from the stored course language when caller sent
    # the default 'en' but the course was generated in Hindi/Tamil/etc.
    lang = _resolve_lang(lang, record)

    # Skip scenes that already have a completed or in-progress render for this lang.
    # Failed renders are NOT skipped so re-calling generate-all re-tries them.
    # Key: (lesson_ref, scene_index) — scene_index may be None for old item-level jobs.
    active_scene_pairs = {
        (j.lesson_ref, j.scene_index)
        for j in video_job_store.list_for_script(script_id)
        if j.status in ("completed", "pending", "processing") and j.lang == lang
    }

    jobs_created: list[dict] = []
    jobs_skipped: list[str]  = []

    # For HeyGen styles stagger submits by 3 s each so the API isn't hit all at once.
    _heygen_stagger = 3.0 if style in _HEYGEN_STYLES else 0.0

    async def _staggered_lesson(job, les, delay: float) -> None:
        if delay:
            await asyncio.sleep(delay)
        await render_lesson_in_background(job, les)

    async def _staggered_item(job, item, delay: float) -> None:
        if delay:
            await asyncio.sleep(delay)
        await render_item_in_background(job, item)

    modules = course.get("modules", [])
    if modules:
        # Standard course — one job per scene per lesson
        job_index = 0
        for mod in modules:
            m_num = int(mod.get("module_number", 1))
            for les in mod.get("lessons", []):
                l_num = int(les.get("lesson_number", 1))
                lesson_ref = f"module_{m_num}_lesson_{l_num}"
                n_scenes = count_lesson_scenes(les)
                for scene_idx in range(n_scenes):
                    if (lesson_ref, scene_idx) in active_scene_pairs:
                        jobs_skipped.append(f"{lesson_ref}_scene_{scene_idx}")
                        continue
                    job = video_job_store.create(
                        script_id=script_id,
                        lesson_ref=lesson_ref,
                        lang=lang,
                        style=style,
                        voice=voice,
                        scene_index=scene_idx,
                    )
                    background_tasks.add_task(
                        _staggered_lesson, job, les, job_index * _heygen_stagger
                    )
                    jobs_created.append({
                        "render_id": job.render_id,
                        "lesson_ref": lesson_ref,
                        "scene_index": scene_idx,
                    })
                    job_index += 1
    else:
        # Custom / blueprint course — one job per renderable item (already scene-level)
        job_index = 0
        for i, item in enumerate(course.get("items", [])):
            if item.get("type") not in ("slide", "closing_slide"):
                continue
            lesson_ref = f"item_{i}"
            if (lesson_ref, None) in active_scene_pairs:
                jobs_skipped.append(lesson_ref)
                continue
            job = video_job_store.create(
                script_id=script_id,
                lesson_ref=lesson_ref,
                lang=lang,
                style=style,
                voice=voice,
            )
            background_tasks.add_task(
                _staggered_item, job, item, job_index * _heygen_stagger
            )
            jobs_created.append(
                {"render_id": job.render_id, "lesson_ref": lesson_ref}
            )
            job_index += 1

    if not jobs_created and not jobs_skipped:
        raise HTTPException(400, "No renderable lessons found in this course script.")

    return {
        "script_id":    script_id,
        "style":        style,
        "lang":         lang,
        "jobs_started": len(jobs_created),
        "jobs_skipped": len(jobs_skipped),
        "jobs":         jobs_created,
    }


@router.get("/renders/{render_id}", response_model=VideoRenderStatus)
def get_render_status(render_id: str):
    """Poll the status of a video render job."""
    job = video_job_store.get(render_id)
    if not job:
        raise HTTPException(404, f"Render job '{render_id}' not found.")
    return _job_to_status(job)


@router.get("/renders/{render_id}/stream")
def stream_video(render_id: str, request: Request):
    """
    Stream the rendered MP4 for inline <video> playback.
    Supports HTTP Range requests (206 Partial Content) so the Flutter
    video_player / browser can seek without re-downloading the whole file.
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

    path      = Path(job.video_path)
    file_size = path.stat().st_size
    range_hdr = request.headers.get("range", "")

    m = re.match(r"bytes=(\d+)-(\d*)", range_hdr) if range_hdr else None
    if m:
        start = int(m.group(1))
        end   = int(m.group(2)) if m.group(2) else file_size - 1
        end   = min(end, file_size - 1)
        if start >= file_size:
            raise HTTPException(
                416,
                "Range Not Satisfiable",
                headers={"Content-Range": f"bytes */{file_size}"},
            )
        length = end - start + 1

        def _iter_range():
            with open(path, "rb") as f:
                f.seek(start)
                remaining = length
                while remaining > 0:
                    chunk = f.read(min(65536, remaining))
                    if not chunk:
                        break
                    remaining -= len(chunk)
                    yield chunk

        return StreamingResponse(
            _iter_range(),
            status_code=206,
            media_type="video/mp4",
            headers={
                "Content-Range":  f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(length),
                "Accept-Ranges":  "bytes",
            },
        )

    # Full file response (no Range header) — still advertise range support
    return FileResponse(
        path=str(path),
        media_type="video/mp4",
        headers={
            "Accept-Ranges":  "bytes",
            "Content-Length": str(file_size),
        },
    )


@router.get("/renders/{render_id}/download")
def download_video(render_id: str):
    """
    Download the rendered MP4 as a file attachment.
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

    scene_suffix = f"_scene{job.scene_index}" if job.scene_index is not None else ""
    filename = f"{job.lesson_ref}{scene_suffix}_{job.lang}.mp4"
    return FileResponse(
        path=job.video_path,
        media_type="video/mp4",
        filename=filename,
    )


@router.get("/scripts/{script_id}/renders")
def list_script_renders(script_id: str):
    """List all render jobs for a course script."""
    jobs = video_job_store.list_for_script(script_id)
    return {
        "script_id": script_id,
        "renders":   [_job_to_status(j) for j in jobs],
        "total":     len(jobs),
    }


@router.get("/heygen-credits")
def heygen_credits():
    """Return remaining HeyGen credits (null if not configured)."""
    from modules.video.generators.heygen_render import remaining_credits, is_configured
    if not is_configured():
        return {"configured": False, "remaining": None}
    bal = remaining_credits()
    return {"configured": True, "remaining": bal}


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
