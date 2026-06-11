"""ORM models for upload and course-generation jobs."""

from __future__ import annotations

import time

from sqlalchemy import Column, Float, Integer, String
from sqlalchemy.orm import Mapped

from api.db import Base


class UploadJobRow(Base):
    """Tracks a single document-upload + ingestion job."""

    __tablename__ = "upload_jobs"

    job_id:         Mapped[str]            = Column(String, primary_key=True)
    filename:       Mapped[str]            = Column(String, nullable=False)
    status:         Mapped[str]            = Column(String, nullable=False, default="pending")
    error:          Mapped[str | None]     = Column(String)
    chunks_created: Mapped[int | None]     = Column(Integer)
    started_at:     Mapped[float]          = Column(Float, nullable=False, default=time.time)
    finished_at:    Mapped[float | None]   = Column(Float)


class CourseJobRow(Base):
    """Tracks a single AI course-generation job."""

    __tablename__ = "course_generation_jobs"

    job_id:             Mapped[str]          = Column(String, primary_key=True)
    source_file:        Mapped[str]          = Column(String, nullable=False)
    status:             Mapped[str]          = Column(String, nullable=False, default="pending")
    error:              Mapped[str | None]   = Column(String)
    # Full course dict serialised as JSON text — can be large (100 KB+)
    course_script_json: Mapped[str | None]   = Column(String)
    started_at:         Mapped[float]        = Column(Float, nullable=False, default=time.time)
    total_lessons:      Mapped[int]          = Column(Integer, nullable=False, default=0)
    completed_lessons:  Mapped[int]          = Column(Integer, nullable=False, default=0)
