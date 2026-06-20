"""ORM model for video render jobs."""

from __future__ import annotations

from sqlalchemy import Column, Float, Integer, String
from sqlalchemy.orm import Mapped

from api.db import Base


class VideoRenderRow(Base):
    """One row per video render job (one lesson × one language × one style)."""

    __tablename__ = "video_renders"

    render_id:   Mapped[str]          = Column(String, primary_key=True)
    script_id:   Mapped[str]          = Column(String, nullable=False, index=True)
    lesson_ref:  Mapped[str]          = Column(String, nullable=False)
    scene_index: Mapped[int | None]   = Column(Integer)
    lang:        Mapped[str]          = Column(String, nullable=False, default="en")
    style:       Mapped[str]          = Column(String, nullable=False, default="modern")
    status:      Mapped[str]          = Column(String, nullable=False, default="pending")
    video_path:  Mapped[str | None]   = Column(String)
    error:       Mapped[str | None]   = Column(String)
    tts_engine:  Mapped[str]          = Column(String, nullable=False, default="")
    voice:       Mapped[str]          = Column(String, nullable=False, default="")
    started_at:  Mapped[float]        = Column(Float, nullable=False)
    finished_at: Mapped[float | None] = Column(Float)
