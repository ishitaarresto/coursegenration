"""
api/db.py -- SQLAlchemy database setup.

Supports two databases transparently:
  - SQLite   (default, zero-install) — set DATABASE_URL=sqlite:///./lms.db or omit it
  - PostgreSQL (production-ready)    — set DATABASE_URL=postgresql://user:pass@host/db

Usage
-----
    from api.db import SessionLocal, get_db, init_db

    # FastAPI dependency (in routers)
    def my_route(db: Session = Depends(get_db)): ...

    # Direct use (in singleton stores)
    with SessionLocal() as db:
        db.add(row)
        db.commit()

    # One-time at startup (in main.py lifespan)
    init_db()
"""

from __future__ import annotations

import os

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, sessionmaker, Session

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./lms.db")

_is_postgres = DATABASE_URL.startswith(("postgresql://", "postgres://"))

if _is_postgres:
    engine = create_engine(
        DATABASE_URL,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=10,
    )
else:
    # SQLite — single-file, bundled with Python, no installation needed
    engine = create_engine(
        DATABASE_URL,
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )

    @event.listens_for(engine, "connect")
    def _set_wal_mode(dbapi_conn, _conn_rec):
        dbapi_conn.execute("PRAGMA journal_mode=WAL")
        dbapi_conn.execute("PRAGMA foreign_keys=ON")


SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


class Base(DeclarativeBase):
    pass


def get_db():
    """FastAPI dependency — yields a DB session and always closes it."""
    db: Session = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """
    Create every table that doesn't exist yet.
    Safe to call on every startup — CREATE TABLE IF NOT EXISTS semantics.
    """
    import api.models  # noqa: F401 — registers all ORM models with Base
    Base.metadata.create_all(bind=engine)
    db_type = "PostgreSQL" if _is_postgres else "SQLite"
    print(f"[db] {db_type} database initialised (all tables ready).")
