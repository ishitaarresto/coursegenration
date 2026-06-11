"""
scripts/migrate_to_sqlite.py -- One-time migration from JSON files to lms.db.

What this script does
---------------------
1. Reads  jobs.json           -> upload_jobs + course_generation_jobs tables
2. Reads  tutor_sessions.json -> tutor_sessions table
3. Reads  video_renders.json  -> video_renders table
4. Reads  compat_ids.json     -> compat_ids + compat_counters tables
5. Reads  course_scripts/*.json -> course_scripts table
6. Copies progress.db tables  -> lesson_records, quiz_attempts, weak_topics in lms.db
7. Renames each source file to *.bak (originals are kept, never deleted)

Run once from the project root:
    python scripts/migrate_to_sqlite.py

Safe to re-run — existing DB rows are skipped (INSERT OR IGNORE / upsert logic).
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import sys
import time
from pathlib import Path

# Make sure the project root is on the Python path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# Change working directory to project root so db path resolves correctly
import os
os.chdir(ROOT)


def main() -> None:
    print("=" * 60)
    print("Arresto LMS - JSON to SQLite migration")
    print("=" * 60)

    # Create all tables
    from api.db import init_db, SessionLocal, engine
    init_db()

    total_migrated = 0

    # ── 1. jobs.json ──────────────────────────────────────────────────────────
    jobs_file = ROOT / "jobs.json"
    if jobs_file.exists():
        print("\n[1/6] Migrating jobs.json ...")
        from api.models.jobs import UploadJobRow, CourseJobRow
        raw = json.loads(jobs_file.read_text(encoding="utf-8"))
        with SessionLocal() as db:
            for d in raw.get("uploads", []):
                if db.get(UploadJobRow, d["job_id"]) is None:
                    db.add(UploadJobRow(
                        job_id=d["job_id"],
                        filename=d.get("filename", ""),
                        status=d.get("status", "completed"),
                        error=d.get("error"),
                        chunks_created=d.get("chunks_created"),
                        started_at=d.get("started_at", time.time()),
                        finished_at=d.get("finished_at"),
                    ))
                    total_migrated += 1
            for d in raw.get("courses", []):
                if db.get(CourseJobRow, d["job_id"]) is None:
                    db.add(CourseJobRow(
                        job_id=d["job_id"],
                        source_file=d.get("source_file", ""),
                        status=d.get("status", "completed"),
                        error=d.get("error"),
                        course_script_json=json.dumps(d["course_script"]) if d.get("course_script") else None,
                        started_at=d.get("started_at", time.time()),
                        total_lessons=d.get("total_lessons", 0),
                        completed_lessons=d.get("completed_lessons", 0),
                    ))
                    total_migrated += 1
            db.commit()
        _backup(jobs_file)
        print(f"   OK Migrated {len(raw.get('uploads', []))} upload jobs, "
              f"{len(raw.get('courses', []))} course jobs.")
    else:
        print("\n[1/6] jobs.json not found — skipped.")

    # ── 2. tutor_sessions.json ────────────────────────────────────────────────
    sessions_file = ROOT / "tutor_sessions.json"
    if sessions_file.exists():
        print("\n[2/6] Migrating tutor_sessions.json ...")
        from api.models.sessions import TutorSessionRow
        raw = json.loads(sessions_file.read_text(encoding="utf-8"))
        count = 0
        with SessionLocal() as db:
            for d in raw.get("sessions", []):
                if db.get(TutorSessionRow, d["session_id"]) is None:
                    db.add(TutorSessionRow(
                        session_id=d["session_id"],
                        source_file=d.get("source_file", ""),
                        course_title=d.get("course_title", ""),
                        target_audience=d.get("target_audience", ""),
                        learner_id=d.get("learner_id", "anonymous"),
                        current_module=d.get("current_module", 1),
                        current_lesson=d.get("current_lesson", 1),
                        created_at=d.get("created_at", time.time()),
                        updated_at=d.get("updated_at", time.time()),
                        lesson_started_at=d.get("lesson_started_at"),
                        awaiting_checkpoint=d.get("awaiting_checkpoint", False),
                        checkpoint_type=d.get("checkpoint_type", ""),
                        current_lesson_checkpointed=d.get("current_lesson_checkpointed", False),
                        module_checkpoint_done=d.get("module_checkpoint_done", False),
                        history_json=json.dumps(d.get("history", [])),
                        course_script_json=json.dumps(d["course_script"]) if d.get("course_script") else None,
                        pending_questions_json=json.dumps(d.get("pending_questions", {})),
                        pending_checkpoint_qids_json=json.dumps(d.get("pending_checkpoint_qids", [])),
                        checkpoint_answers_json=json.dumps(d.get("checkpoint_answers", [])),
                    ))
                    count += 1
                    total_migrated += 1
            db.commit()
        _backup(sessions_file)
        print(f"   OK Migrated {count} sessions.")
    else:
        print("\n[2/6] tutor_sessions.json not found — skipped.")

    # ── 3. video_renders.json ─────────────────────────────────────────────────
    renders_file = ROOT / "video_renders.json"
    if renders_file.exists():
        print("\n[3/6] Migrating video_renders.json ...")
        from api.models.renders import VideoRenderRow
        raw = json.loads(renders_file.read_text(encoding="utf-8"))
        count = 0
        with SessionLocal() as db:
            for d in raw:
                if db.get(VideoRenderRow, d["render_id"]) is None:
                    db.add(VideoRenderRow(
                        render_id=d["render_id"],
                        script_id=d.get("script_id", ""),
                        lesson_ref=d.get("lesson_ref", ""),
                        lang=d.get("lang", "en"),
                        style=d.get("style", "modern"),
                        status=d.get("status", "completed"),
                        video_path=d.get("video_path"),
                        error=d.get("error"),
                        tts_engine=d.get("tts_engine", ""),
                        started_at=d.get("started_at", time.time()),
                        finished_at=d.get("finished_at"),
                    ))
                    count += 1
                    total_migrated += 1
            db.commit()
        _backup(renders_file)
        print(f"   OK Migrated {count} video render jobs.")
    else:
        print("\n[3/6] video_renders.json not found — skipped.")

    # ── 4. compat_ids.json ────────────────────────────────────────────────────
    compat_file = ROOT / "compat_ids.json"
    if compat_file.exists():
        print("\n[4/6] Migrating compat_ids.json ...")
        from api.models.compat import CompatIdRow, CompatCounterRow
        raw = json.loads(compat_file.read_text(encoding="utf-8"))
        count = 0
        with SessionLocal() as db:
            for int_id_str, uuid_str in raw.get("jobs", {}).items():
                _insert_compat_id(db, CompatIdRow, "job", int(int_id_str), uuid_str)
                count += 1
            for int_id_str, uuid_str in raw.get("courses", {}).items():
                _insert_compat_id(db, CompatIdRow, "course", int(int_id_str), uuid_str)
                count += 1
            for int_id_str, uuid_str in raw.get("renders", {}).items():
                _insert_compat_id(db, CompatIdRow, "render", int(int_id_str), uuid_str)
                count += 1
            for int_id_str, info in raw.get("lessons", {}).items():
                script_id = info.get("script_id", "")
                mod_num   = info.get("module_number")
                les_num   = info.get("lesson_number")
                synthetic = f"{script_id}:m{mod_num}:l{les_num}"
                _insert_compat_id(db, CompatIdRow, "lesson", int(int_id_str),
                                  synthetic, mod_num, les_num)
                count += 1
            # Counters
            for entity, key in [("job", "next_job"), ("course", "next_course"),
                                 ("render", "next_render"), ("lesson", "next_lesson")]:
                row = db.get(CompatCounterRow, entity)
                if row is None:
                    db.add(CompatCounterRow(entity_type=entity, next_id=raw.get(key, 1)))
                else:
                    row.next_id = max(row.next_id, raw.get(key, 1))
            db.commit()
        _backup(compat_file)
        total_migrated += count
        print(f"   OK Migrated {count} compat ID mappings.")
    else:
        print("\n[4/6] compat_ids.json not found — skipped.")

    # ── 5. course_scripts/*.json ──────────────────────────────────────────────
    scripts_dir = ROOT / "course_scripts"
    if scripts_dir.exists():
        script_files = [f for f in scripts_dir.glob("*.json") if f.name != "_index.json"]
        print(f"\n[5/6] Migrating {len(script_files)} course script files ...")
        from api.models.courses import CourseScriptRow
        count = 0
        with SessionLocal() as db:
            for sf in script_files:
                try:
                    d = json.loads(sf.read_text(encoding="utf-8"))
                    script_id = d.get("script_id", sf.stem)
                    if db.get(CourseScriptRow, script_id) is None:
                        cs = d.get("course_script", {})
                        db.add(CourseScriptRow(
                            script_id=script_id,
                            source_file=d.get("source_file", ""),
                            course_title=d.get("course_title", "Untitled"),
                            target_audience=d.get("target_audience", ""),
                            instructions=d.get("instructions"),
                            use_knowledge_base=bool(d.get("use_knowledge_base", False)),
                            generated_at=d.get("generated_at", time.time()),
                            total_lessons=d.get("total_lessons", 0),
                            estimated_duration_min=d.get("estimated_duration_min", 0),
                            course_script_json=json.dumps(cs, ensure_ascii=False),
                        ))
                        count += 1
                        total_migrated += 1
                except Exception as exc:
                    print(f"   WARNING: skipped {sf.name}: {exc}")
            db.commit()
        if count:
            # Backup the whole directory
            bak_dir = scripts_dir.parent / "course_scripts_bak"
            if not bak_dir.exists():
                shutil.copytree(str(scripts_dir), str(bak_dir))
                print(f"   OK Backed up course_scripts/ -> course_scripts_bak/")
        print(f"   OK Migrated {count} course scripts.")
    else:
        print("\n[5/6] course_scripts/ not found — skipped.")

    # ── 6. progress.db ───────────────────────────────────────────────────────
    progress_db = ROOT / "progress.db"
    if progress_db.exists():
        print("\n[6/6] Migrating progress.db tables ...")
        tables = ["lesson_records", "quiz_attempts", "weak_topics"]
        count = 0
        src = sqlite3.connect(str(progress_db))
        src.row_factory = sqlite3.Row
        lms_conn = engine.raw_connection()
        try:
            for table in tables:
                try:
                    rows = src.execute(f"SELECT * FROM {table}").fetchall()
                    if not rows:
                        continue
                    cols = rows[0].keys()
                    placeholders = ", ".join(["?"] * len(cols))
                    col_names    = ", ".join(cols)
                    sql = (f"INSERT OR IGNORE INTO {table} ({col_names}) "
                           f"VALUES ({placeholders})")
                    lms_conn.executemany(sql, [tuple(r) for r in rows])
                    count += len(rows)
                    print(f"   OK {table}: {len(rows)} rows")
                except Exception as exc:
                    print(f"   WARNING: {table} skipped: {exc}")
            lms_conn.commit()
        finally:
            src.close()
            lms_conn.close()
        _backup(progress_db)
        total_migrated += count
        print(f"   OK Migrated {count} progress rows.")
    else:
        print("\n[6/6] progress.db not found — skipped.")

    # ── Summary ───────────────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print(f"Migration complete. {total_migrated} total rows inserted into lms.db.")
    print("Original files renamed to *.bak — delete them when satisfied.")
    print("=" * 60)


def _backup(path: Path) -> None:
    bak = path.with_suffix(path.suffix + ".bak")
    shutil.copy2(str(path), str(bak))
    print(f"   -> backed up to {bak.name}")


def _insert_compat_id(db, Model, entity_type, int_id, uuid_str,
                      module_number=None, lesson_number=None):
    from sqlalchemy import and_
    existing = (
        db.query(Model)
        .filter(and_(Model.entity_type == entity_type, Model.int_id == int_id))
        .first()
    )
    if existing is None:
        db.add(Model(
            entity_type=entity_type,
            int_id=int_id,
            uuid_str=uuid_str,
            module_number=module_number,
            lesson_number=lesson_number,
        ))


if __name__ == "__main__":
    main()
