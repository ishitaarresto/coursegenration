"""ORM models for learner progress tracking.

Mirrors the exact schema that modules/progress/store.py creates with raw
sqlite3.  Having these as SQLAlchemy models means:
  - init_db() creates the tables if they don't exist (new installs)
  - The migration script can copy rows from progress.db into lms.db
  - Future code can optionally use the ORM layer instead of raw sqlite3
"""

from __future__ import annotations

from sqlalchemy import Column, Float, Index, Integer, String
from sqlalchemy.orm import Mapped

from api.db import Base


class LessonRecordRow(Base):
    __tablename__ = "lesson_records"

    learner_id:              Mapped[str]          = Column(String, primary_key=True)
    course_id:               Mapped[str]          = Column(String, primary_key=True)
    module_idx:              Mapped[int]          = Column(Integer, primary_key=True)
    lesson_idx:              Mapped[int]          = Column(Integer, primary_key=True)
    started_at:              Mapped[float]        = Column(Float, nullable=False)
    completed_at:            Mapped[float | None] = Column(Float)
    checkpoint_score:        Mapped[float | None] = Column(Float)
    module_checkpoint_score: Mapped[float | None] = Column(Float)


class QuizAttemptRow(Base):
    __tablename__ = "quiz_attempts"

    id:             Mapped[str]          = Column(String, primary_key=True)
    learner_id:     Mapped[str]          = Column(String, nullable=False)
    course_id:      Mapped[str]          = Column(String, nullable=False)
    module_idx:     Mapped[int]          = Column(Integer, nullable=False)
    lesson_idx:     Mapped[int]          = Column(Integer, nullable=False)
    question_id:    Mapped[str]          = Column(String, nullable=False)
    question_text:  Mapped[str | None]   = Column(String)
    learner_answer: Mapped[str | None]   = Column(String)
    correct_answer: Mapped[str | None]   = Column(String)
    is_correct:     Mapped[int]          = Column(Integer, nullable=False)
    topic_tag:      Mapped[str | None]   = Column(String)
    quiz_type:      Mapped[str | None]   = Column(String)
    attempted_at:   Mapped[float]        = Column(Float, nullable=False)

    __table_args__ = (
        Index(
            "idx_attempts_key",
            "learner_id", "course_id", "module_idx", "lesson_idx", "quiz_type",
        ),
    )


class WeakTopicRow(Base):
    __tablename__ = "weak_topics"

    learner_id:   Mapped[str]          = Column(String, primary_key=True)
    course_id:    Mapped[str]          = Column(String, primary_key=True)
    topic:        Mapped[str]          = Column(String, primary_key=True)
    miss_count:   Mapped[int]          = Column(Integer, nullable=False, default=0)
    total_count:  Mapped[int]          = Column(Integer, nullable=False, default=0)
    last_seen_at: Mapped[float | None] = Column(Float)


class AssessmentAttemptRow(Base):
    __tablename__ = "assessment_attempts"

    id:              Mapped[str]   = Column(String, primary_key=True)
    learner_id:      Mapped[str]   = Column(String, nullable=False, index=True)
    script_id:       Mapped[str]   = Column(String, nullable=False, index=True)
    score:           Mapped[int]   = Column(Integer, nullable=False)
    correct:         Mapped[int]   = Column(Integer, nullable=False)
    total:           Mapped[int]   = Column(Integer, nullable=False)
    passed:          Mapped[int]   = Column(Integer, nullable=False)  # 0/1 sqlite compat
    elapsed_seconds: Mapped[int]   = Column(Integer, nullable=False, default=0)
    answers_json:    Mapped[str]   = Column(String, nullable=False, default='{}')
    taken_at:        Mapped[float] = Column(Float, nullable=False)
