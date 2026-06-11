"""ORM model for AI tutor sessions."""

from __future__ import annotations

from sqlalchemy import Boolean, Column, Float, Integer, String
from sqlalchemy.orm import Mapped

from api.db import Base


class TutorSessionRow(Base):
    """
    One row per active tutor session.

    Nested structures (conversation history, pending quiz questions,
    checkpoint state) are stored as JSON text columns — avoids a
    normalised 4-table schema for data that is always read/written as
    a whole unit.
    """

    __tablename__ = "tutor_sessions"

    session_id:      Mapped[str]   = Column(String, primary_key=True)
    source_file:     Mapped[str]   = Column(String, nullable=False)
    course_title:    Mapped[str]   = Column(String, nullable=False)
    target_audience: Mapped[str]   = Column(String, nullable=False, default="")
    learner_id:      Mapped[str]   = Column(String, nullable=False, default="anonymous", index=True)
    current_module:  Mapped[int]   = Column(Integer, nullable=False, default=1)
    current_lesson:  Mapped[int]   = Column(Integer, nullable=False, default=1)
    created_at:      Mapped[float] = Column(Float, nullable=False)
    updated_at:      Mapped[float] = Column(Float, nullable=False)
    lesson_started_at: Mapped[float | None] = Column(Float)

    # ── Checkpoint / quiz state ────────────────────────────────────────────────
    awaiting_checkpoint:          Mapped[bool] = Column(Boolean, nullable=False, default=False)
    checkpoint_type:              Mapped[str]  = Column(String, nullable=False, default="")
    current_lesson_checkpointed:  Mapped[bool] = Column(Boolean, nullable=False, default=False)
    module_checkpoint_done:       Mapped[bool] = Column(Boolean, nullable=False, default=False)

    # ── JSON columns (lists / dicts serialised as text) ───────────────────────
    # [ {role, content}, ... ]
    history_json:               Mapped[str] = Column(String, nullable=False, default="[]")
    # Full course dict (may be None for sessions without an embedded script)
    course_script_json:         Mapped[str | None] = Column(String)
    # { question_id: {question_id, question, options, correct_answer, ...} }
    pending_questions_json:     Mapped[str] = Column(String, nullable=False, default="{}")
    # [ question_id, ... ] — IDs of the active checkpoint batch
    pending_checkpoint_qids_json: Mapped[str] = Column(String, nullable=False, default="[]")
    # [ true, false, ... ] — answer result per checkpoint question
    checkpoint_answers_json:    Mapped[str] = Column(String, nullable=False, default="[]")
