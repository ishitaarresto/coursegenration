"""SQLAlchemy models owned by the Course Generation module."""
from __future__ import annotations

import enum
from datetime import datetime, timezone

from sqlalchemy import JSON, DateTime, Enum, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class JobStatus(str, enum.Enum):
    pending = "pending"
    running = "running"
    completed = "completed"
    failed = "failed"


class CourseMode(str, enum.Enum):
    quick = "quick"
    detailed = "detailed"


class Job(Base):
    __tablename__ = "jobs"

    id: Mapped[int] = mapped_column(primary_key=True)
    status: Mapped[JobStatus] = mapped_column(Enum(JobStatus), default=JobStatus.pending)
    progress: Mapped[int] = mapped_column(Integer, default=0)
    step: Mapped[str] = mapped_column(String(200), default="queued")
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    course_id: Mapped[int | None] = mapped_column(ForeignKey("courses.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class Course(Base):
    __tablename__ = "courses"

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(500))
    description: Mapped[str] = mapped_column(Text, default="")
    learning_objectives: Mapped[list] = mapped_column(JSON, default=list)
    mode: Mapped[CourseMode] = mapped_column(Enum(CourseMode), default=CourseMode.detailed)
    languages: Mapped[list] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(50), default="draft")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    modules: Mapped[list["Module"]] = relationship(
        back_populates="course", cascade="all, delete-orphan", order_by="Module.order"
    )


class Module(Base):
    __tablename__ = "modules"

    id: Mapped[int] = mapped_column(primary_key=True)
    course_id: Mapped[int] = mapped_column(ForeignKey("courses.id"))
    order: Mapped[int] = mapped_column(Integer, default=0)
    title: Mapped[str] = mapped_column(String(500))
    objectives: Mapped[list] = mapped_column(JSON, default=list)

    course: Mapped["Course"] = relationship(back_populates="modules")
    lessons: Mapped[list["Lesson"]] = relationship(
        back_populates="module", cascade="all, delete-orphan", order_by="Lesson.order"
    )


class Lesson(Base):
    __tablename__ = "lessons"

    id: Mapped[int] = mapped_column(primary_key=True)
    module_id: Mapped[int] = mapped_column(ForeignKey("modules.id"))
    order: Mapped[int] = mapped_column(Integer, default=0)
    title: Mapped[str] = mapped_column(String(500))
    learning_objectives: Mapped[list] = mapped_column(JSON, default=list)
    key_takeaways: Mapped[list] = mapped_column(JSON, default=list)
    simplified_explanation: Mapped[str] = mapped_column(Text, default="")
    real_world_examples: Mapped[list] = mapped_column(JSON, default=list)
    safety_scenarios: Mapped[list] = mapped_column(JSON, default=list)
    summary: Mapped[str] = mapped_column(Text, default="")
    narration_script: Mapped[str] = mapped_column(Text, default="")

    module: Mapped["Module"] = relationship(back_populates="lessons")
    slides: Mapped[list["Slide"]] = relationship(
        back_populates="lesson", cascade="all, delete-orphan", order_by="Slide.order"
    )
    video_renders: Mapped[list["VideoRender"]] = relationship(
        back_populates="lesson", cascade="all, delete-orphan"
    )


class Slide(Base):
    __tablename__ = "slides"

    id: Mapped[int] = mapped_column(primary_key=True)
    lesson_id: Mapped[int] = mapped_column(ForeignKey("lessons.id"))
    order: Mapped[int] = mapped_column(Integer, default=0)
    type: Mapped[str] = mapped_column(String(50), default="content")
    payload: Mapped[dict] = mapped_column(JSON, default=dict)

    lesson: Mapped["Lesson"] = relationship(back_populates="slides")


class VideoRender(Base):
    """Stores the path to a generated lesson video per language."""
    __tablename__ = "video_renders"

    id: Mapped[int] = mapped_column(primary_key=True)
    lesson_id: Mapped[int] = mapped_column(ForeignKey("lessons.id"))
    lang: Mapped[str] = mapped_column(String(20), default="en")
    status: Mapped[JobStatus] = mapped_column(Enum(JobStatus), default=JobStatus.pending)
    video_path: Mapped[str | None] = mapped_column(String(500), nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    lesson: Mapped["Lesson"] = relationship(back_populates="video_renders")
