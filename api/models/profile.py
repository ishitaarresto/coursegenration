"""ORM model for learner profile (display name + avatar)."""

from __future__ import annotations

import time

from sqlalchemy import Column, Float, String
from sqlalchemy.orm import Mapped

from api.db import Base


class LearnerProfileRow(Base):
    __tablename__ = "learner_profiles"

    learner_id:   Mapped[str]        = Column(String, primary_key=True)
    display_name: Mapped[str | None] = Column(String)
    avatar_url:   Mapped[str | None] = Column(String)
    updated_at:   Mapped[float]      = Column(Float, nullable=False, default=time.time)
