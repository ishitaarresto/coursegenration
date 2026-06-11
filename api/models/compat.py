"""ORM models for the integer↔UUID compat ID mapping layer."""

from __future__ import annotations

from sqlalchemy import Column, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped

from api.db import Base


class CompatIdRow(Base):
    """Maps a monotonic integer ID to a UUID for one entity type."""

    __tablename__ = "compat_ids"

    id:            Mapped[int]          = Column(Integer, primary_key=True, autoincrement=True)
    entity_type:   Mapped[str]          = Column(String, nullable=False)   # job|course|render|lesson
    int_id:        Mapped[int]          = Column(Integer, nullable=False, index=True)
    uuid_str:      Mapped[str]          = Column(String, nullable=False)
    # Lesson extras
    module_number: Mapped[int | None]   = Column(Integer)
    lesson_number: Mapped[int | None]   = Column(Integer)

    __table_args__ = (
        UniqueConstraint("entity_type", "int_id", name="uq_compat_entity_int"),
    )


class CompatCounterRow(Base):
    """One row per entity type, holding the next available integer ID."""

    __tablename__ = "compat_counters"

    entity_type: Mapped[str] = Column(String, primary_key=True)
    next_id:     Mapped[int] = Column(Integer, nullable=False, default=1)
