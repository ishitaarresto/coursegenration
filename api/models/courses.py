"""ORM model for saved course scripts."""

from __future__ import annotations

from sqlalchemy import Boolean, Column, Float, Integer, String
from sqlalchemy.orm import Mapped

from api.db import Base


class CourseScriptRow(Base):
    """
    One row per completed course script.

    Metadata columns allow fast list/search queries without deserialising
    the full course JSON.  The complete course structure (modules, lessons,
    narration scripts, etc.) is stored in course_script_json.
    """

    __tablename__ = "course_scripts"

    script_id:           Mapped[str]        = Column(String, primary_key=True)
    source_file:         Mapped[str]        = Column(String, nullable=False, index=True)
    course_title:        Mapped[str]        = Column(String, nullable=False)
    target_audience:     Mapped[str]        = Column(String, nullable=False, default="")
    instructions:        Mapped[str | None] = Column(String)
    use_knowledge_base:  Mapped[bool]       = Column(Boolean, nullable=False, default=False)
    generated_at:        Mapped[float]      = Column(Float, nullable=False)
    total_lessons:       Mapped[int]        = Column(Integer, nullable=False, default=0)
    estimated_duration_min: Mapped[int]     = Column(Integer, nullable=False, default=0)
    # Full course dict — stored as JSON text
    course_script_json:  Mapped[str]        = Column(String, nullable=False)
    # Generation settings (added post-launch — migrated at startup via init_db)
    language:                  Mapped[str]  = Column(String, nullable=False, default="English")
    difficulty:                Mapped[str]  = Column(String, nullable=False, default="")
    published:                 Mapped[bool] = Column(Boolean, nullable=False, default=False)
    # Assessment configuration set by admin in the generator wizard
    assessment_num_questions:  Mapped[int]  = Column(Integer, nullable=False, default=5)
    assessment_pass_pct:       Mapped[int]  = Column(Integer, nullable=False, default=70)
    assessment_time_min:       Mapped[int]  = Column(Integer, nullable=False, default=30)
    assessment_retakes:        Mapped[int]  = Column(Integer, nullable=False, default=3)
    # Cached assessment questions JSON (generated from instructions + course content)
    assessment_questions_json: Mapped[str | None] = Column(String)
