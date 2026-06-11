"""
api/course_library.py -- Persistent storage for completed course scripts.

Backed by lms.db (SQLAlchemy) instead of individual JSON files.
The public API is identical to the old file-based version so all callers
(routers, dependencies.py, audio router) require zero changes.

Usage
-----
    from api.course_library import library

    entry   = library.save(script_id, source_file, course_title, ...)
    entries = library.list_all()       # index rows, no script body
    record  = library.get(script_id)   # full record including course_script
    record  = library.update(script_id, course_script, course_title)
    existed = library.delete(script_id)
"""

from __future__ import annotations

import json
import time
from typing import Any


class CourseLibrary:
    """Saves and retrieves completed course scripts from lms.db."""

    # -- Public API -----------------------------------------------------------

    def save(
        self,
        script_id:          str,
        source_file:        str,
        course_title:       str,
        target_audience:    str,
        course_script:      dict,
        instructions:       str | None = None,
        use_knowledge_base: bool = False,
    ) -> dict:
        """
        Persist a completed course script.
        Returns an index entry dict (identical shape to the old JSON format,
        without the course_script body).
        """
        generated_at = time.time()
        duration_min = course_script.get("estimated_total_duration_min", 0)

        if course_script.get("items"):
            total_lessons = sum(
                1 for item in course_script["items"]
                if item.get("type") in ("slide", "closing_slide")
            )
        else:
            total_lessons = sum(
                len(m.get("lessons", []))
                for m in course_script.get("modules", [])
            )

        from api.db import SessionLocal
        from api.models.courses import CourseScriptRow
        with SessionLocal() as db:
            row = db.get(CourseScriptRow, script_id)
            if row is None:
                row = CourseScriptRow(script_id=script_id)
                db.add(row)
            row.source_file          = source_file
            row.course_title         = course_title
            row.target_audience      = target_audience
            row.instructions         = instructions
            row.use_knowledge_base   = use_knowledge_base
            row.generated_at         = generated_at
            row.total_lessons        = total_lessons
            row.estimated_duration_min = duration_min
            row.course_script_json   = json.dumps(course_script, ensure_ascii=False)
            db.commit()

        print(f"[course_library] Saved '{course_title}' ({total_lessons} lessons) → lms.db")
        return self._row_to_index_entry(row)

    def list_all(self) -> list[dict]:
        """Return all index entries (no script body), newest first."""
        from api.db import SessionLocal
        from api.models.courses import CourseScriptRow
        from sqlalchemy import desc
        with SessionLocal() as db:
            rows = db.query(CourseScriptRow).order_by(desc(CourseScriptRow.generated_at)).all()
        return [self._row_to_index_entry(r) for r in rows]

    def get(self, script_id: str) -> dict | None:
        """Return the full record including course_script dict, or None."""
        from api.db import SessionLocal
        from api.models.courses import CourseScriptRow
        with SessionLocal() as db:
            row = db.get(CourseScriptRow, script_id)
        if row is None:
            return None
        entry = self._row_to_index_entry(row)
        entry["course_script"] = json.loads(row.course_script_json)
        return entry

    def update(
        self,
        script_id: str,
        course_script: dict,
        course_title: str | None = None,
    ) -> dict | None:
        """Replace the stored course_script (and optionally title). Returns updated record."""
        from api.db import SessionLocal
        from api.models.courses import CourseScriptRow
        with SessionLocal() as db:
            row = db.get(CourseScriptRow, script_id)
            if row is None:
                return None
            row.course_script_json = json.dumps(course_script, ensure_ascii=False)
            if course_title is not None:
                row.course_title = course_title
            db.commit()
            # Re-fetch within the session so we return consistent data
            db.refresh(row)
        print(f"[course_library] Updated script '{script_id}'.")
        entry = self._row_to_index_entry(row)
        entry["course_script"] = course_script
        return entry

    def delete(self, script_id: str) -> bool:
        """Delete a script. Returns True if it existed."""
        from api.db import SessionLocal
        from api.models.courses import CourseScriptRow
        with SessionLocal() as db:
            row = db.get(CourseScriptRow, script_id)
            if row is None:
                return False
            db.delete(row)
            db.commit()
        return True

    # -- Internal helpers ------------------------------------------------------

    @staticmethod
    def _row_to_index_entry(row: Any) -> dict:
        """Convert an ORM row to the dict shape the rest of the codebase expects."""
        return {
            "script_id":              row.script_id,
            "source_file":            row.source_file,
            "course_title":           row.course_title,
            "target_audience":        row.target_audience,
            "instructions":           row.instructions,
            "use_knowledge_base":     row.use_knowledge_base,
            "generated_at":           row.generated_at,
            "total_lessons":          row.total_lessons,
            "estimated_duration_min": row.estimated_duration_min,
        }


# Singleton used throughout the API
library = CourseLibrary()
