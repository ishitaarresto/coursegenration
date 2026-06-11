"""
api/compat_store.py

Maps integer IDs (used by the Author Studio frontend) to the UUID strings
used internally by the Arresto LMS backend.

Backed by lms.db (SQLAlchemy) instead of compat_ids.json.
Thread-safe via a threading.Lock on in-memory counter operations.
The public API (add_job, get_job_uuid, etc.) is unchanged.
"""

from __future__ import annotations

from threading import Lock


class CompatStore:

    def __init__(self) -> None:
        self._lock = Lock()

    # -- Internal helpers ------------------------------------------------------

    def _get_counter(self, entity_type: str) -> int:
        from api.db import SessionLocal
        from api.models.compat import CompatCounterRow
        with SessionLocal() as db:
            row = db.get(CompatCounterRow, entity_type)
            return row.next_id if row else 1

    def _bump_counter(self, entity_type: str) -> int:
        """Atomically read and increment the counter. Returns the CURRENT value."""
        from api.db import SessionLocal
        from api.models.compat import CompatCounterRow
        with SessionLocal() as db:
            row = db.get(CompatCounterRow, entity_type)
            if row is None:
                row = CompatCounterRow(entity_type=entity_type, next_id=1)
                db.add(row)
            current = row.next_id
            row.next_id = current + 1
            db.commit()
        return current

    def _find_or_create(self, entity_type: str, uuid_str: str,
                        module_number: int | None = None,
                        lesson_number: int | None = None) -> int:
        """Return existing int_id for uuid_str, or allocate a new one."""
        from api.db import SessionLocal
        from api.models.compat import CompatIdRow
        with SessionLocal() as db:
            existing = (
                db.query(CompatIdRow)
                .filter_by(entity_type=entity_type, uuid_str=uuid_str)
                .first()
            )
            if existing:
                return existing.int_id
            int_id = self._bump_counter(entity_type)
            row = CompatIdRow(
                entity_type=entity_type,
                int_id=int_id,
                uuid_str=uuid_str,
                module_number=module_number,
                lesson_number=lesson_number,
            )
            db.add(row)
            db.commit()
        return int_id

    def _uuid_for(self, entity_type: str, int_id: int) -> str | None:
        from api.db import SessionLocal
        from api.models.compat import CompatIdRow
        with SessionLocal() as db:
            row = (
                db.query(CompatIdRow)
                .filter_by(entity_type=entity_type, int_id=int_id)
                .first()
            )
        return row.uuid_str if row else None

    # -- Job IDs ---------------------------------------------------------------

    def add_job(self, job_uuid: str) -> int:
        with self._lock:
            return self._find_or_create("job", job_uuid)

    def get_job_uuid(self, int_id: int) -> str | None:
        return self._uuid_for("job", int_id)

    # -- Course IDs ------------------------------------------------------------

    def add_course(self, script_uuid: str) -> int:
        with self._lock:
            return self._find_or_create("course", script_uuid)

    def get_course_uuid(self, int_id: int) -> str | None:
        return self._uuid_for("course", int_id)

    # -- Lesson IDs ------------------------------------------------------------

    def register_lessons(self, script_id: str, modules: list[dict]) -> dict:
        """
        Ensure every module/lesson combo has an integer ID.
        Returns mapping of (module_number, lesson_number) → int_id.
        """
        result: dict[tuple, int] = {}
        with self._lock:
            for mod in modules:
                mod_num = mod.get("module_number", 1)
                for les in mod.get("lessons", []):
                    les_num = les.get("lesson_number", 1)
                    # Use a synthetic UUID that encodes the lesson identity so
                    # _find_or_create deduplicates correctly across restarts.
                    synthetic = f"{script_id}:m{mod_num}:l{les_num}"
                    int_id = self._find_or_create(
                        "lesson", synthetic,
                        module_number=mod_num,
                        lesson_number=les_num,
                    )
                    result[(mod_num, les_num)] = int_id
        return result

    def get_lesson_info(self, int_id: int) -> dict | None:
        from api.db import SessionLocal
        from api.models.compat import CompatIdRow
        with SessionLocal() as db:
            row = (
                db.query(CompatIdRow)
                .filter_by(entity_type="lesson", int_id=int_id)
                .first()
            )
        if not row:
            return None
        # uuid_str is "script_id:mX:lY" — extract script_id from it
        parts = row.uuid_str.split(":")
        script_id = parts[0] if parts else row.uuid_str
        return {
            "script_id":     script_id,
            "module_number": row.module_number,
            "lesson_number": row.lesson_number,
        }

    # -- Render IDs ------------------------------------------------------------

    def add_render(self, render_uuid: str) -> int:
        with self._lock:
            return self._find_or_create("render", render_uuid)

    def get_render_uuid(self, int_id: int) -> str | None:
        return self._uuid_for("render", int_id)


compat_store = CompatStore()
