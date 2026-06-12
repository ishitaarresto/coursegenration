"""
api/routers/audio.py

GET    /api/v1/audio/{script_id}/{module_num}/{lesson_num}  Stream lesson audio (on-demand, cached)
GET    /api/v1/audio/{script_id}                            List lessons with cached audio
POST   /api/v1/audio/generate/{script_id}                  Optional pre-warm: synthesise all lessons
GET    /api/v1/audio/jobs/{job_id}                          Poll pre-warm job status

On-demand caching
-----------------
Every GET /{script_id}/{module}/{lesson} request:
  1. Looks up the current narration from the course library.
  2. Checks the cache: does m{n}_l{n}.mp3 exist AND does its companion
     m{n}_l{n}.sha256 match the SHA-256 of the current narration text?
  3. Cache hit  → FileResponse immediately (no API call).
  4. Cache miss → call Sarvam TTS → write MP3 + .sha256 → FileResponse.

Editing a course and replaying a lesson automatically regenerates that
lesson's audio because the narration hash no longer matches.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import re
import time
import uuid

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from fastapi import APIRouter, BackgroundTasks, HTTPException, Request
from fastapi.responses import FileResponse

logger = logging.getLogger("arresto.audio")

from api.config import settings
from api.course_library import library
from api.schemas import (
    AudioGenerateResponse,
    AudioJobStatus,
    AudioLessonInfo,
    AudioListResponse,
)

router = APIRouter(prefix="/api/v1/audio", tags=["Audio / TTS"])


# -- Cache helpers ---------------------------------------------------------------

def _audio_dir(script_id: str) -> Path:
    return settings.upload_dir / "audio" / script_id


def _audio_path(script_id: str, module_num: int, lesson_num: int) -> Path:
    return _audio_dir(script_id) / f"m{module_num}_l{lesson_num}.mp3"


def _hash_path(mp3_path: Path) -> Path:
    return mp3_path.with_suffix(".sha256")


def _narration_hash(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def _is_cache_valid(mp3_path: Path, narration: str) -> bool:
    """True only if the MP3 exists and was generated from the current narration text."""
    if not mp3_path.exists():
        return False
    h_path = _hash_path(mp3_path)
    if not h_path.exists():
        return False
    return h_path.read_text(encoding="utf-8").strip() == _narration_hash(narration)


def _write_cache(mp3_path: Path, audio_bytes: bytes, narration: str) -> None:
    """Write MP3 bytes and its companion hash file, then evict if over the size cap."""
    mp3_path.parent.mkdir(parents=True, exist_ok=True)
    mp3_path.write_bytes(audio_bytes)
    _hash_path(mp3_path).write_text(_narration_hash(narration), encoding="utf-8")
    _evict_audio_cache(settings.audio_cache_max_mb)


def _evict_audio_cache(max_mb: int) -> None:
    """Delete oldest MP3s (and their .sha256 siblings) until total cache is under max_mb."""
    base = settings.upload_dir / "audio"
    if not base.exists():
        return
    entries: list[tuple[float, int, Path]] = []
    for mp3 in base.rglob("*.mp3"):
        try:
            st = mp3.stat()
            entries.append((st.st_mtime, st.st_size, mp3))
        except OSError:
            pass
    total = sum(s for _, s, _ in entries)
    limit = max_mb * 1024 * 1024
    if total <= limit:
        return
    entries.sort()  # oldest mtime first
    for _mtime, size, path in entries:
        if total <= limit:
            break
        try:
            path.unlink(missing_ok=True)
            _hash_path(path).unlink(missing_ok=True)
            total -= size
        except OSError:
            pass


def _get_narration(course_script: dict, module_num: int, lesson_num: int) -> str | None:
    """Return the narration text for a specific module/lesson, or None.

    For custom/blueprint courses (items[] only), the Flutter item player uses the
    convention module=1, lesson=itemIndex+1, so we decode that back to an item index.
    """
    for mod in course_script.get("modules", []):
        if mod["module_number"] == module_num:
            for les in mod.get("lessons", []):
                if les["lesson_number"] == lesson_num:
                    return les.get("narration_script", "").strip() or None

    # Custom/blueprint fallback: items use module=1, lesson=itemIndex+1
    items = course_script.get("items", [])
    if items and module_num == 1:
        item_index = lesson_num - 1
        if 0 <= item_index < len(items):
            item = items[item_index]
            narration = item.get("narration", item.get("narration_script", "")).strip()
            return narration or None

    return None


def _collect_lessons(course_script: dict) -> list[tuple[int, int, str]]:
    """Return (module_number, lesson_number, narration_script) for every lesson.

    For custom/blueprint courses, encodes item index as module=1, lesson=itemIndex+1
    to match the convention used by the Flutter item player.
    """
    result = []
    for mod in course_script.get("modules", []):
        for les in mod.get("lessons", []):
            narration = les.get("narration_script", "").strip()
            if narration:
                result.append((mod["module_number"], les["lesson_number"], narration))

    # Custom/blueprint courses have items instead of modules
    if not result:
        for idx, item in enumerate(course_script.get("items", [])):
            narration = item.get("narration", item.get("narration_script", "")).strip()
            if narration:
                result.append((1, idx + 1, narration))

    return result


# -- TTS engine access -----------------------------------------------------------

def _get_tts_engine(request: Request) -> Any:
    engine = getattr(request.app.state, "tts_engine", None)
    if engine is None:
        raise HTTPException(
            status_code=503,
            detail=(
                "TTS is not available. "
                "Set SARVAM_API_KEY in your .env file and restart the server."
            ),
        )
    return engine


# -- In-memory pre-warm job store ------------------------------------------------

@dataclass
class _AudioJob:
    job_id:            str
    script_id:         str
    status:            str = "pending"
    total_lessons:     int = 0
    completed_lessons: int = 0
    errors:            list[str] = field(default_factory=list)
    started_at:        float = field(default_factory=time.time)

    def to_schema(self) -> AudioJobStatus:
        return AudioJobStatus(
            job_id=self.job_id,
            script_id=self.script_id,
            status=self.status,
            total_lessons=self.total_lessons,
            completed_lessons=self.completed_lessons,
            errors=self.errors,
        )


_audio_jobs: dict[str, _AudioJob] = {}


# -- Background pre-warm --------------------------------------------------------

def _sync_prewarm(job: _AudioJob, lessons: list[tuple[int, int, str]], engine: Any) -> None:
    """
    Pre-warm synthesis. Uses the same hash-based cache as on-demand generation:
    a lesson is skipped when its MP3 is already valid for the current narration.
    """
    job.total_lessons = len(lessons)
    job.status        = "processing"

    for mod_num, les_num, narration in lessons:
        out_path = _audio_path(job.script_id, mod_num, les_num)

        if _is_cache_valid(out_path, narration):
            job.completed_lessons += 1
            continue

        try:
            logger.info("Pre-warm m%d_l%d (%d chars) ...", mod_num, les_num, len(narration))
            audio_bytes = engine.synthesize_bytes(narration)
            _write_cache(out_path, audio_bytes, narration)
            logger.info("  -> %s (%d KB)", out_path.name, out_path.stat().st_size // 1024)
        except Exception as exc:
            err = f"m{mod_num}_l{les_num}: {exc}"
            job.errors.append(err)
            logger.error("Pre-warm failed: %s", err)

        job.completed_lessons += 1

    job.status = "completed" if not job.errors else "completed_with_errors"
    logger.info(
        "Pre-warm done for '%s' (%d/%d lessons, %d errors)",
        job.script_id, job.completed_lessons, job.total_lessons, len(job.errors),
    )


async def _prewarm_in_background(
    job: _AudioJob, lessons: list[tuple[int, int, str]], engine: Any
) -> None:
    await asyncio.to_thread(_sync_prewarm, job, lessons, engine)


# -- Routes ---------------------------------------------------------------------

@router.get("/{script_id}/{module_num}/{lesson_num}")
async def stream_lesson_audio(
    script_id:  str,
    module_num: int,
    lesson_num: int,
    request:    Request,
):
    """
    Stream MP3 audio for a specific lesson.

    **On-demand with caching:**
    - Cache hit (narration unchanged) → served instantly from disk.
    - Cache miss (new lesson or narration edited) → generated now via Sarvam TTS,
      cached to disk, then served. Generation takes ~3–15 s depending on length.

    Cache validity is determined by a SHA-256 hash of the narration text stored
    in a companion `.sha256` file next to each MP3.  Editing the course and
    replaying a lesson automatically regenerates only that lesson's audio.

    Requires SARVAM_API_KEY to be configured.
    """
    record = library.get(script_id)
    if not record:
        raise HTTPException(
            status_code=404,
            detail=f"Course script '{script_id}' not found in the library.",
        )

    narration = _get_narration(record["course_script"], module_num, lesson_num)
    if not narration:
        raise HTTPException(
            status_code=404,
            detail=f"No narration found for module {module_num}, lesson {lesson_num}.",
        )

    mp3_path = _audio_path(script_id, module_num, lesson_num)

    if not _is_cache_valid(mp3_path, narration):
        tts_engine = _get_tts_engine(request)
        try:
            logger.info(
                "On-demand TTS: m%d_l%d (%d chars) ...", module_num, lesson_num, len(narration)
            )
            audio_bytes = await asyncio.to_thread(
                tts_engine.synthesize_bytes, narration
            )
            await asyncio.to_thread(_write_cache, mp3_path, audio_bytes, narration)
            logger.info("  -> cached %s (%d KB)", mp3_path.name, mp3_path.stat().st_size // 1024)
        except Exception as exc:
            raise HTTPException(
                status_code=500,
                detail=f"TTS generation failed: {exc}",
            )

    return FileResponse(
        path=str(mp3_path),
        media_type="audio/mpeg",
        filename=mp3_path.name,
    )


@router.get("/jobs/{job_id}", response_model=AudioJobStatus)
def get_audio_job(job_id: str):
    """Poll the status of a pre-warm job."""
    job = _audio_jobs.get(job_id)
    if not job:
        raise HTTPException(
            status_code=404,
            detail=f"Audio job '{job_id}' not found.",
        )
    return job.to_schema()


@router.get("/{script_id}", response_model=AudioListResponse)
def list_audio(script_id: str):
    """
    List lessons that have a cached MP3 ready for this course.

    Only MP3s that exist on disk are listed, regardless of whether their
    hash is still valid.  A stale hash means the next play request will
    regenerate that lesson's audio automatically.
    """
    audio_dir = _audio_dir(script_id)
    if not audio_dir.exists():
        return AudioListResponse(script_id=script_id, total_available=0, lessons=[])

    pattern = re.compile(r"m(\d+)_l(\d+)\.mp3$")
    lessons: list[AudioLessonInfo] = []

    for mp3 in sorted(audio_dir.glob("*.mp3")):
        match = pattern.match(mp3.name)
        if match:
            lessons.append(AudioLessonInfo(
                module_number=int(match.group(1)),
                lesson_number=int(match.group(2)),
                filename=mp3.name,
                size_bytes=mp3.stat().st_size,
            ))

    lessons.sort(key=lambda x: (x.module_number, x.lesson_number))
    return AudioListResponse(
        script_id=script_id,
        total_available=len(lessons),
        lessons=lessons,
    )


@router.post("/generate/{script_id}", response_model=AudioGenerateResponse, status_code=202)
async def prewarm_audio(
    script_id:        str,
    background_tasks: BackgroundTasks,
    request:          Request,
):
    """
    **Optional pre-warm**: synthesise MP3s for all lessons in a course upfront.

    You do **not** need to call this before playing a lesson — the playback
    endpoint (`GET /{script_id}/{module}/{lesson}`) generates audio on demand
    and caches it.  Use this endpoint when you want zero latency on first play
    for every lesson simultaneously (e.g. before a training session goes live).

    Lessons whose cached MP3 already matches the current narration are skipped.
    Only lessons with changed or missing audio are re-generated.

    Poll `GET /api/v1/audio/jobs/{job_id}` to track progress.
    """
    tts_engine = _get_tts_engine(request)

    record = library.get(script_id)
    if not record:
        raise HTTPException(
            status_code=404,
            detail=f"Course script '{script_id}' not found in the library.",
        )

    lessons = _collect_lessons(record["course_script"])
    if not lessons:
        raise HTTPException(
            status_code=422,
            detail="Course has no lessons with narration scripts.",
        )

    job = _AudioJob(
        job_id=str(uuid.uuid4()),
        script_id=script_id,
        total_lessons=len(lessons),
    )
    _audio_jobs[job.job_id] = job
    background_tasks.add_task(_prewarm_in_background, job, lessons, tts_engine)

    return AudioGenerateResponse(
        job_id=job.job_id,
        script_id=script_id,
        status="processing",
        message=(
            f"Pre-warm started for {len(lessons)} lessons. "
            f"Poll /api/v1/audio/jobs/{job.job_id} to track progress."
        ),
        total_lessons=len(lessons),
    )
