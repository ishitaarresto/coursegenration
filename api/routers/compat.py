"""
api/routers/compat.py  --  Author Studio compatibility layer

Exposes the same API contract as the LMSarresto3 frontend expects, using integer
IDs and the /api/ prefix (without /v1/).  All routes delegate to the same
underlying services as the /api/v1/ routes; no data is duplicated.

Endpoints
---------
POST /api/courses/generate                                  Generate from raw text
GET  /api/jobs/{id}                                         Poll generation job
GET  /api/courses/{id}                                      Get full course
POST /api/courses/import                                    Import a pre-built JSON
GET  /api/courses/{course_id}/lessons/{lesson_id}/slides    Render slide HTML
POST /api/courses/{course_id}/lessons/{lesson_id}/render    Render video
GET  /api/renders/{render_id}/status                        Poll render job
GET  /api/courses/{course_id}/lessons/{lesson_id}/video     Download video
GET  /api/courses/{course_id}/lessons/{lesson_id}/cost      Credit cost estimate
GET  /api/courses/{course_id}/lessons/{lesson_id}/quiz      Inline quiz questions
GET  /api/languages                                         Supported TTS languages
GET  /api/styles                                            Available video styles
"""

from __future__ import annotations

import uuid as _uuid_mod

from fastapi import APIRouter, BackgroundTasks, Body, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import BaseModel

from api.compat_store import compat_store
from api.config import settings
from api.course_library import library
from api.dependencies import (
    _QUIZ_MARKERS,
    generate_from_text_in_background,
    generate_micro_from_text_in_background,
    get_embedder,
    get_vector_store,
    job_store,
)
from modules.video.job_store import video_job_store
from modules.video.render_engine import render_lesson_in_background

router = APIRouter(prefix="/api", tags=["Author Studio (compat)"])


# ── Helpers ────────────────────────────────────────────────────────────────────

def _lesson_from_script(course_script: dict, module_number: int, lesson_number: int) -> dict | None:
    for mod in course_script.get("modules", []):
        if mod.get("module_number") == module_number:
            for les in mod.get("lessons", []):
                if les.get("lesson_number") == lesson_number:
                    return les
    return None


def _to_compat_course(script_id: str, record: dict) -> dict:
    """Transform the internal library record to the shape the Author Studio expects."""
    course = record["course_script"]
    course_int_id = compat_store.add_course(script_id)

    modules = course.get("modules", [])
    lesson_map = compat_store.register_lessons(script_id, modules)

    compat_modules = []
    for mod in modules:
        mod_num = mod.get("module_number", 1)
        compat_lessons = []
        for les in mod.get("lessons", []):
            les_num = les.get("lesson_number", 1)
            les_int_id = lesson_map.get((mod_num, les_num), 0)
            compat_lessons.append({
                "id":                    les_int_id,
                "title":                 les.get("lesson_title", les.get("title", "")),
                "summary":               les.get("summary", ""),
                "simplified_explanation": les.get("simplified_explanation", ""),
                "key_takeaways":         les.get("key_takeaways", []),
                "real_world_examples":   les.get("real_world_examples", []),
                "safety_scenarios":      les.get("safety_scenarios", []),
            })
        compat_modules.append({
            "title":   mod.get("module_title", mod.get("title", "")),
            "lessons": compat_lessons,
        })

    result = {
        "id":                  course_int_id,
        "title":               course.get("course_title", record.get("course_title", "")),
        "description":         course.get("description", course.get("course_description", "")),
        "learning_objectives": course.get("learning_objectives", []),
        "modules":             compat_modules,
    }
    # Expose flat items[] for micro/quiz courses so the Author Studio can render them.
    if course.get("items"):
        result["items"] = course["items"]
    return result


# ── Request models ─────────────────────────────────────────────────────────────

class CompatGenerateRequest(BaseModel):
    content_text: str
    mode:         str       = "detailed"   # "quick" | "detailed"
    languages:    list[str] = ["en"]


# ── Routes ─────────────────────────────────────────────────────────────────────

@router.post("/courses/generate")
async def generate_course(
    request:          CompatGenerateRequest,
    background_tasks: BackgroundTasks,
    vector_store      = Depends(get_vector_store),
    embedder          = Depends(get_embedder),
):
    """
    Generate a course from pasted raw text.

    Accepts `content_text` (the full training manual / script pasted by the user),
    `mode` ("quick" for a short preview, "detailed" for a full course), and
    `languages` (list of BCP-47 codes — controls video TTS language later).

    Returns `{id}` — an integer job ID.  Poll `GET /api/jobs/{id}` until
    `status == "completed"`, then fetch the course with `GET /api/courses/{course_id}`.
    """
    if not settings.anthropic_api_key:
        raise HTTPException(status_code=503, detail="ANTHROPIC_API_KEY not configured.")
    if not request.content_text.strip():
        raise HTTPException(status_code=400, detail="content_text cannot be empty.")

    job    = job_store.create_course("inline_content")
    int_id = compat_store.add_job(job.job_id)

    # Auto-detect: if the text has structured quiz markers use the single-call
    # micro-course generator (produces items[] with MCQ/Flashcard/True-False).
    # Otherwise use the full module/lesson pipeline.
    has_quiz = any(m in request.content_text for m in _QUIZ_MARKERS)
    if has_quiz:
        background_tasks.add_task(
            generate_micro_from_text_in_background,
            job,
            settings.anthropic_api_key,
            vector_store,
            embedder,
            request.content_text,
        )
    else:
        background_tasks.add_task(
            generate_from_text_in_background,
            job,
            settings.anthropic_api_key,
            vector_store,
            embedder,
            request.content_text,
            request.mode,
        )
    return {"id": int_id}


@router.get("/jobs/{job_id}")
def get_job(job_id: int):
    """
    Poll a course generation job.

    Returns `{id, status, progress, step, course_id, error}`.
    `status` is one of: `processing`, `completed`, `failed`.
    `course_id` is populated (integer) once `status == "completed"`.
    """
    job_uuid = compat_store.get_job_uuid(job_id)
    if not job_uuid:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found.")

    job = job_store.get_course(job_uuid)
    if not job:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found.")

    schema = job.to_schema()

    # Register course ID once the job is done so the frontend can immediately
    # call GET /api/courses/{course_id} with an integer ID.
    course_id = None
    if job.status == "completed" and job.course_script:
        course_id = compat_store.add_course(job_uuid)   # job_uuid == script_id
        modules = job.course_script.get("modules", [])
        if modules:
            compat_store.register_lessons(job_uuid, modules)

    return {
        "id":        job_id,
        "status":    schema.status,
        "progress":  schema.progress,
        "step":      schema.step,
        "course_id": course_id,
        "error":     schema.error,
    }


@router.get("/courses/{course_id}")
def get_course(course_id: int):
    """
    Retrieve a generated course by its integer ID.

    Returns the full course object with modules, lessons, and all Author Studio
    fields (summary, key_takeaways, real_world_examples, safety_scenarios).
    """
    script_uuid = compat_store.get_course_uuid(course_id)
    if not script_uuid:
        raise HTTPException(status_code=404, detail=f"Course {course_id} not found.")

    record = library.get(script_uuid)
    if not record:
        raise HTTPException(status_code=404, detail=f"Course {course_id} not found in library.")

    return _to_compat_course(script_uuid, record)


@router.post("/courses/import")
def import_course(payload: dict = Body(...)):
    """
    Import a pre-built course JSON instantly (no AI generation).

    The payload can be:
    - A flat `course_script` dict  (course_title, modules, …)
    - A wrapped dict  {"course_script": {…}}

    Returns `{course_id, message}` where `course_id` is an integer.
    """
    # Unwrap if the user pasted a wrapped format
    if "course_script" in payload and isinstance(payload["course_script"], dict):
        course_script = payload["course_script"]
    else:
        course_script = payload

    course_title    = course_script.get("course_title", course_script.get("title", "Imported Course"))
    source_file     = course_script.get("source_file", "imported")
    target_audience = course_script.get("target_audience", "learners")

    script_id = str(_uuid_mod.uuid4())
    library.save(
        script_id=script_id,
        source_file=source_file,
        course_title=course_title,
        target_audience=target_audience,
        course_script=course_script,
        instructions=None,
        use_knowledge_base=False,
    )

    int_id = compat_store.add_course(script_id)
    modules = course_script.get("modules", [])
    if modules:
        compat_store.register_lessons(script_id, modules)

    total_lessons = sum(len(m.get("lessons", [])) for m in modules)
    return {
        "course_id": int_id,
        "message":   f"Course imported with {total_lessons} lessons.",
    }


@router.get("/courses/{course_id}/lessons/{lesson_id}/slides")
def get_slides(course_id: int, lesson_id: int):
    """
    Return an HTML page displaying the slide content for a lesson.
    Opens in an external browser tab.
    """
    lesson_info = compat_store.get_lesson_info(lesson_id)
    if not lesson_info:
        raise HTTPException(status_code=404, detail=f"Lesson {lesson_id} not found.")

    record = library.get(lesson_info["script_id"])
    if not record:
        raise HTTPException(status_code=404, detail="Course not found.")

    lesson = _lesson_from_script(
        record["course_script"],
        lesson_info["module_number"],
        lesson_info["lesson_number"],
    )
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson content not found.")

    slide   = lesson.get("slide_content", {})
    title   = slide.get("title", lesson.get("lesson_title", "Lesson"))
    bullets = slide.get("bullets", [])
    notes   = slide.get("speaker_notes", "")
    narration = lesson.get("narration_script", "")

    bullet_html = "".join(f"<li>{b}</li>" for b in bullets)
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>{title}</title>
  <style>
    *{{box-sizing:border-box;margin:0;padding:0}}
    body{{font-family:'Segoe UI',Arial,sans-serif;background:#f1f5f9;padding:40px;color:#1e293b}}
    .slide{{background:#fff;border-radius:12px;padding:36px 40px;max-width:860px;margin:0 auto;
            box-shadow:0 4px 20px rgba(0,0,0,.08)}}
    h1{{font-size:1.7rem;color:#1e3a8a;margin-bottom:20px;border-bottom:3px solid #2563eb;
        padding-bottom:12px}}
    ul{{padding-left:24px;margin-bottom:24px}}
    li{{font-size:1.05rem;line-height:1.9;color:#334155}}
    .notes{{font-size:.9rem;color:#64748b;font-style:italic;border-top:1px solid #e2e8f0;
            padding-top:14px;margin-top:8px}}
    .narration{{margin-top:24px;background:#f8fafc;border-radius:8px;padding:20px;
                border-left:4px solid #2563eb}}
    .narration h2{{font-size:1rem;color:#2563eb;margin-bottom:10px}}
    .narration p{{font-size:.95rem;line-height:1.75;color:#475569}}
  </style>
</head>
<body>
  <div class="slide">
    <h1>{title}</h1>
    <ul>{bullet_html}</ul>
    {'<p class="notes">'+notes+'</p>' if notes else ''}
    {'<div class="narration"><h2>Narration Script</h2><p>'+narration+'</p></div>' if narration else ''}
  </div>
</body>
</html>"""
    return HTMLResponse(html)


@router.post("/courses/{course_id}/lessons/{lesson_id}/render")
async def render_video(
    course_id:        int,
    lesson_id:        int,
    background_tasks: BackgroundTasks,
    lang:             str = Query("en"),
    style:            str = Query("animated_scene"),
    course_type:      str = Query("detailed"),
    economy:          str = Query("lean"),
):
    """
    Start a video render for a lesson.

    Defaults to `style=animated_scene` (HeyGen) when HEYGEN_API_KEY is set;
    automatically falls back to the free Claude Animated renderer if the key
    is missing or the style is not a HeyGen style.

    Returns `{render_id}` (integer).  Poll `GET /api/renders/{render_id}/status`.
    """
    if style in ("animated_scene", "whiteboard_doodle", "hybrid"):
        from modules.video.generators.heygen_render import is_configured as _heygen_ok
        if not _heygen_ok():
            # Graceful fallback: no key → use free renderer instead of hard error
            style = "claude_native"

    lesson_info = compat_store.get_lesson_info(lesson_id)
    if not lesson_info:
        raise HTTPException(status_code=404, detail=f"Lesson {lesson_id} not found.")

    record = library.get(lesson_info["script_id"])
    if not record:
        raise HTTPException(status_code=404, detail="Course not found.")

    mod_num = lesson_info["module_number"]
    les_num = lesson_info["lesson_number"]

    lesson_data = _lesson_from_script(record["course_script"], mod_num, les_num)
    if not lesson_data:
        raise HTTPException(status_code=404, detail="Lesson content not found.")

    lesson_ref = f"module_{mod_num}_lesson_{les_num}"
    job = video_job_store.create(
        script_id=lesson_info["script_id"],
        lesson_ref=lesson_ref,
        lang=lang,
        style=style,
    )
    background_tasks.add_task(render_lesson_in_background, job, lesson_data)

    render_int_id = compat_store.add_render(job.render_id)
    return {"render_id": render_int_id}


@router.get("/renders/{render_id}/status")
def get_render_status(render_id: int):
    """
    Poll a video render job.

    Returns `{render_id, status, error}`.
    `status` is one of: `pending`, `running`, `completed`, `failed`.
    """
    render_uuid = compat_store.get_render_uuid(render_id)
    if not render_uuid:
        raise HTTPException(status_code=404, detail=f"Render {render_id} not found.")

    job = video_job_store.get(render_uuid)
    if not job:
        raise HTTPException(status_code=404, detail=f"Render {render_id} not found.")

    # Map internal status names to what the Author Studio frontend expects
    _status_map = {
        "pending":    "pending",
        "processing": "running",
        "completed":  "completed",
        "failed":     "failed",
    }
    return {
        "render_id": render_id,
        "status":    _status_map.get(job.status, job.status),
        "error":     job.error,
    }


@router.get("/courses/{course_id}/lessons/{lesson_id}/video")
def get_video(course_id: int, lesson_id: int, lang: str = Query("en")):
    """
    Stream the rendered MP4 for a lesson.

    The video must have been rendered first via
    `POST /api/courses/{course_id}/lessons/{lesson_id}/render`.
    """
    lesson_info = compat_store.get_lesson_info(lesson_id)
    if not lesson_info:
        raise HTTPException(status_code=404, detail=f"Lesson {lesson_id} not found.")

    script_id = lesson_info["script_id"]
    mod_num   = lesson_info["module_number"]
    les_num   = lesson_info["lesson_number"]
    lesson_ref = f"module_{mod_num}_lesson_{les_num}"

    jobs = video_job_store.list_for_script(script_id)
    completed = [
        j for j in jobs
        if j.lesson_ref == lesson_ref
        and j.lang == lang
        and j.status == "completed"
        and j.video_path
    ]
    if not completed:
        raise HTTPException(
            status_code=404,
            detail="Video not ready. Render it first via POST …/render.",
        )

    from pathlib import Path as _Path
    latest = max(completed, key=lambda j: j.started_at)
    if not _Path(latest.video_path).exists():
        raise HTTPException(status_code=404, detail="Video file not found on disk.")

    return FileResponse(
        path=latest.video_path,
        media_type="video/mp4",
        filename=f"lesson_{lesson_id}_{lang}.mp4",
    )


@router.get("/courses/{course_id}/lessons/{lesson_id}/cost")
def get_render_cost(course_id: int, lesson_id: int, economy: str = Query("lean")):
    """
    Return a real credit cost estimate for a video render based on narration length.

    Uses the actual narration script and the economy preset to calculate how many
    HeyGen credits this lesson will consume.  Spends nothing — read-only.
    """
    from modules.video.generators.credit_economy import plan, ECONOMY_PRESETS
    from modules.video.generators.heygen_render import is_configured, remaining_credits

    # Fetch narration text from the course JSON for an accurate estimate
    narration = ""
    lesson_info = compat_store.get_lesson_info(lesson_id)
    if lesson_info:
        record = library.get(lesson_info["script_id"])
        if record:
            lesson = _lesson_from_script(
                record["course_script"],
                lesson_info["module_number"],
                lesson_info["lesson_number"],
            )
            if lesson:
                narration = (
                    lesson.get("narration_script")
                    or lesson.get("simplified_explanation")
                    or lesson.get("lesson_title", "")
                )

    credit_plan = plan(narration, economy)

    if is_configured():
        balance = remaining_credits()
        return {
            **credit_plan,
            "credits_remaining": balance,
            "affordable":        (balance is None) or (balance >= credit_plan["estimated_cost"]),
            "presets":           list(ECONOMY_PRESETS.keys()),
        }
    # Free renderer — no credit cost; show estimated render time (claude_native ~30 s/lesson)
    return {
        **credit_plan,
        "estimated_cost":    0,
        "credits_remaining": None,
        "affordable":        True,
        "will_condense":     False,
        "estimated_seconds": 30,
        "presets":           list(ECONOMY_PRESETS.keys()),
    }


@router.get("/courses/{course_id}/lessons/{lesson_id}/quiz")
def get_lesson_quiz(course_id: int, lesson_id: int, lang: str = Query("en")):
    """
    Return inline MCQ/True-False questions for a lesson video.

    Questions are generated alongside whiteboard-style videos and stored as
    sidecar JSON files.  Returns an empty list for lessons that have no quiz
    file — never an error.
    """
    from pathlib import Path as _Path
    import json as _json

    lesson_info = compat_store.get_lesson_info(lesson_id)
    if not lesson_info:
        return {"questions": []}

    quiz_path = (
        _Path("media") / "whiteboard"
        / str(lesson_id) / f"{lang}.quiz.json"
    )
    if quiz_path.exists():
        try:
            return {"questions": _json.loads(quiz_path.read_text(encoding="utf-8"))}
        except Exception:
            pass
    return {"questions": []}


@router.get("/languages")
def list_languages():
    """
    List supported TTS languages and which engine handles each one.

    Sarvam AI handles Indian languages (hi, ta, te, bn, gu, kn, ml, mr, pa).
    edge-tts handles everything else for free.
    """
    from modules.video.generators.heygen_render import is_configured as _heygen_ok

    _SARVAM = {"hi", "ta", "te", "bn", "gu", "kn", "ml", "mr", "pa", "od"}
    _ALL = ["en", "hi", "ta", "te", "bn", "gu", "kn", "ml", "mr", "pa"]

    return {
        "languages": _ALL,
        "details":   [
            {"code": c, "engine": "sarvam" if c in _SARVAM else "edge-tts"}
            for c in _ALL
        ],
        "sarvam_ready": bool(settings.sarvam_api_key),
        "heygen_ready": _heygen_ok(),
    }


@router.get("/styles")
def list_styles():
    """
    List available video styles with label, engine, and availability.

    Paid styles (HeyGen) are only available when HEYGEN_API_KEY is configured.
    The free claude_native renderer is always available.
    """
    from modules.video.generators.heygen_render import is_configured as _heygen_ok
    heygen_ready = _heygen_ok()

    styles = [
        {
            "key":      "claude_native",
            "label":    "Claude Animated (free)",
            "tagline":  "AI-generated animated scenes — no API key needed.",
            "engine":   "claude",
            "paid":     False,
            "available": True,
        },
        {
            "key":      "animated_scene",
            "label":    "Animated Scene (HeyGen)",
            "tagline":  "Photorealistic animated avatar with scene backgrounds.",
            "engine":   "heygen",
            "paid":     True,
            "available": heygen_ready,
        },
        {
            "key":      "whiteboard_doodle",
            "label":    "Whiteboard Doodle (HeyGen)",
            "tagline":  "Hand-drawn whiteboard animation with voiceover.",
            "engine":   "heygen",
            "paid":     True,
            "available": heygen_ready,
        },
        {
            "key":      "hybrid",
            "label":    "Hybrid (Claude + HeyGen)",
            "tagline":  "Claude-generated scenes enhanced with a HeyGen avatar.",
            "engine":   "hybrid",
            "paid":     True,
            "available": heygen_ready,
        },
    ]
    return {
        "styles": styles,
        "course_types": [
            {"key": "quick",    "label": "Quick Overview",
             "tagline": "One continuous ~15-min video of the whole topic."},
            {"key": "detailed", "label": "Detailed Lessons",
             "tagline": "One in-depth video per lesson in the script."},
        ],
        "heygen_ready": heygen_ready,
    }
