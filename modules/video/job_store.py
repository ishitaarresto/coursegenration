"""
modules/video/job_store.py -- Persistent render job store for video generation.

Backed by lms.db (SQLAlchemy) instead of video_renders.json.
The VideoRenderJob dataclass and VideoJobStore public API are unchanged.
"""

from __future__ import annotations
import logging

logger = logging.getLogger("arresto.video.job_store")

import time
import uuid
from dataclasses import dataclass, field


@dataclass
class VideoRenderJob:
    render_id:   str
    script_id:   str
    lesson_ref:  str
    lang:        str
    style:       str
    status:      str = "pending"
    video_path:  str | None = None
    error:       str | None = None
    started_at:  float = field(default_factory=time.time)
    finished_at: float | None = None
    tts_engine:  str = ""


class VideoJobStore:
    """
    Persists video render jobs to lms.db via SQLAlchemy.
    In-memory dict provides a fast cache for status polling.
    """

    def __init__(self) -> None:
        self._jobs: dict[str, VideoRenderJob] = {}
        self._load()

    # -- Bootstrap -------------------------------------------------------------

    def _load(self) -> None:
        try:
            from api.db import SessionLocal
            from api.models.renders import VideoRenderRow
            with SessionLocal() as db:
                for row in db.query(VideoRenderRow).all():
                    self._jobs[row.render_id] = self._row_to_job(row)
        except Exception as exc:
            logger.warning("Could not load video jobs from DB: %s", exc)

    # -- Persistence -----------------------------------------------------------

    def _upsert(self, job: VideoRenderJob) -> None:
        try:
            from api.db import SessionLocal
            from api.models.renders import VideoRenderRow
            with SessionLocal() as db:
                row = db.get(VideoRenderRow, job.render_id)
                if row is None:
                    row = VideoRenderRow(render_id=job.render_id)
                    db.add(row)
                row.script_id   = job.script_id
                row.lesson_ref  = job.lesson_ref
                row.lang        = job.lang
                row.style       = job.style
                row.status      = job.status
                row.video_path  = job.video_path
                row.error       = job.error
                row.tts_engine  = job.tts_engine
                row.started_at  = job.started_at
                row.finished_at = job.finished_at
                db.commit()
        except Exception as exc:
            logger.warning("Could not persist render job to DB: %s", exc)

    # -- Public API ------------------------------------------------------------

    def create(self, script_id: str, lesson_ref: str, lang: str, style: str) -> VideoRenderJob:
        job = VideoRenderJob(
            render_id=str(uuid.uuid4()),
            script_id=script_id,
            lesson_ref=lesson_ref,
            lang=lang,
            style=style,
        )
        self._jobs[job.render_id] = job
        self._upsert(job)
        return job

    def get(self, render_id: str) -> VideoRenderJob | None:
        return self._jobs.get(render_id.strip())

    def list_for_script(self, script_id: str) -> list[VideoRenderJob]:
        return [j for j in self._jobs.values() if j.script_id == script_id]

    def save(self) -> None:
        """Persist all in-memory jobs (called by render engine after status changes)."""
        for job in self._jobs.values():
            self._upsert(job)

    # -- Internal helpers ------------------------------------------------------

    @staticmethod
    def _row_to_job(row) -> VideoRenderJob:
        return VideoRenderJob(
            render_id=row.render_id,
            script_id=row.script_id,
            lesson_ref=row.lesson_ref,
            lang=row.lang,
            style=row.style,
            status=row.status,
            video_path=row.video_path,
            error=row.error,
            tts_engine=row.tts_engine or "",
            started_at=row.started_at,
            finished_at=row.finished_at,
        )


# Global singleton
video_job_store = VideoJobStore()
