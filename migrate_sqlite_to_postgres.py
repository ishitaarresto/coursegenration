#!/usr/bin/env python3
"""
migrate_sqlite_to_postgres.py

Copies all data from lms.db (SQLite) into the PostgreSQL database
configured via DATABASE_URL in .env.

Steps:
    1. Start PostgreSQL:   docker-compose up -d
    2. Wait ~5 seconds for it to be ready
    3. Run this script:   python migrate_sqlite_to_postgres.py
    4. Start the server:  uvicorn api.main:app --reload
"""

import os
import sys
import io
import sqlite3
from pathlib import Path

# Force UTF-8 output so Hindi/Unicode characters in course data don't crash the print
if hasattr(sys.stdout, "buffer"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "buffer"):
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ── Load .env into os.environ BEFORE importing api.db ─────────────────────────
# api/db.py reads DATABASE_URL at import time via os.getenv(), so we must
# inject .env values into the environment first.
_env_path = Path(".env")
if _env_path.exists():
    for _line in _env_path.read_text(encoding="utf-8").splitlines():
        _line = _line.strip()
        if _line and not _line.startswith("#") and "=" in _line:
            _key, _, _val = _line.partition("=")
            os.environ.setdefault(_key.strip(), _val.strip())

SQLITE_PATH = "lms.db"
POSTGRES_URL = os.environ.get("DATABASE_URL", "")

if not POSTGRES_URL or not POSTGRES_URL.startswith(("postgresql://", "postgres://")):
    print("ERROR: DATABASE_URL in .env must be a PostgreSQL connection string.")
    print(f"  Got: {POSTGRES_URL!r}")
    sys.exit(1)

if not Path(SQLITE_PATH).exists():
    print(f"ERROR: {SQLITE_PATH} not found. Run from the project root.")
    sys.exit(1)

print(f"Source : {SQLITE_PATH}")
print(f"Target : {POSTGRES_URL}")
print()

# ── Boolean columns that need 0/1 → True/False conversion ─────────────────────
BOOL_COLS: dict[str, set[str]] = {
    "course_scripts": {"use_knowledge_base", "published"},
    "tutor_sessions": {
        "awaiting_checkpoint",
        "current_lesson_checkpointed",
        "module_checkpoint_done",
    },
}

# ── Tables to migrate (in this order to respect dependencies) ─────────────────
TABLES = [
    "upload_jobs",
    "course_generation_jobs",
    "course_scripts",
    "tutor_sessions",
    "video_renders",
    "lesson_records",
    "quiz_attempts",
    "weak_topics",
    "assessment_attempts",
    "learner_profiles",
    "notifications",
]


def migrate() -> None:
    # Init PostgreSQL schema
    print("Creating PostgreSQL schema...")
    from api.db import init_db, engine as pg_engine
    init_db()
    print()

    # Open SQLite
    sqlite_conn = sqlite3.connect(SQLITE_PATH)
    sqlite_conn.row_factory = sqlite3.Row

    from sqlalchemy import text

    total_rows = 0

    with pg_engine.connect() as pg_conn:
        for table in TABLES:
            cur = sqlite_conn.cursor()

            # Check table exists in SQLite
            cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                (table,),
            )
            if not cur.fetchone():
                print(f"  {table}: not in SQLite (skipped)")
                continue

            cur.execute(f"SELECT * FROM \"{table}\"")
            rows = cur.fetchall()

            if not rows:
                print(f"  {table}: 0 rows (skipped)")
                continue

            cols = [d[0] for d in cur.description]
            bool_cols = BOOL_COLS.get(table, set())

            col_list = ", ".join(f'"{c}"' for c in cols)
            placeholders = ", ".join(f":{c}" for c in cols)
            sql = text(
                f'INSERT INTO "{table}" ({col_list}) VALUES ({placeholders})'
                f" ON CONFLICT DO NOTHING"
            )

            ok = skipped = errors = 0
            for row in rows:
                data: dict = dict(zip(cols, tuple(row)))

                # Convert SQLite integer booleans → Python booleans
                for col in bool_cols:
                    if col in data and data[col] is not None:
                        data[col] = bool(data[col])

                try:
                    result = pg_conn.execute(sql, data)
                    if result.rowcount == 0:
                        skipped += 1
                    else:
                        ok += 1
                except Exception as exc:
                    errors += 1
                    if errors <= 3:
                        print(f"    WARNING [{table}]: {exc}")

            pg_conn.commit()

            status = f"{ok} migrated"
            if skipped:
                status += f", {skipped} already existed"
            if errors:
                status += f", {errors} errors"
            print(f"  {table}: {status}")
            total_rows += ok

    sqlite_conn.close()
    print()
    print(f"Done — {total_rows} rows migrated to PostgreSQL.")
    print()
    print("Next step:  uvicorn api.main:app --reload")


if __name__ == "__main__":
    migrate()
