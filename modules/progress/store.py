"""
modules/progress/store.py -- SQLite-backed persistence for learner progress.
"""

from __future__ import annotations

import sqlite3
import time
from pathlib import Path

from .models import LessonRecord, QuizAttempt, WeakTopic

_DDL = """
CREATE TABLE IF NOT EXISTS lesson_records (
    learner_id               TEXT    NOT NULL,
    course_id                TEXT    NOT NULL,
    module_idx               INTEGER NOT NULL,
    lesson_idx               INTEGER NOT NULL,
    started_at               REAL    NOT NULL,
    completed_at             REAL,
    checkpoint_score         REAL,
    module_checkpoint_score  REAL,
    PRIMARY KEY (learner_id, course_id, module_idx, lesson_idx)
);

CREATE TABLE IF NOT EXISTS quiz_attempts (
    id             TEXT PRIMARY KEY,
    learner_id     TEXT    NOT NULL,
    course_id      TEXT    NOT NULL,
    module_idx     INTEGER NOT NULL,
    lesson_idx     INTEGER NOT NULL,
    question_id    TEXT    NOT NULL,
    question_text  TEXT,
    learner_answer TEXT,
    correct_answer TEXT,
    is_correct     INTEGER NOT NULL,
    topic_tag      TEXT,
    quiz_type      TEXT,
    attempted_at   REAL    NOT NULL
);

CREATE TABLE IF NOT EXISTS weak_topics (
    learner_id   TEXT    NOT NULL,
    course_id    TEXT    NOT NULL,
    topic        TEXT    NOT NULL,
    miss_count   INTEGER DEFAULT 0,
    total_count  INTEGER DEFAULT 0,
    last_seen_at REAL,
    PRIMARY KEY (learner_id, course_id, topic)
);

CREATE INDEX IF NOT EXISTS idx_attempts_key
    ON quiz_attempts (learner_id, course_id, module_idx, lesson_idx, quiz_type);
"""


class ProgressStore:
    def __init__(self, db_path: str = "progress.db") -> None:
        self._path = db_path
        self._init()

    def _connect(self) -> sqlite3.Connection:
        con = sqlite3.connect(self._path)
        con.row_factory = sqlite3.Row
        return con

    def _init(self) -> None:
        with self._connect() as con:
            con.executescript(_DDL)

    # -- Lesson records ----------------------------------------------------------

    def upsert_lesson_record(self, r: LessonRecord) -> None:
        sql = """
        INSERT INTO lesson_records
            (learner_id, course_id, module_idx, lesson_idx, started_at,
             completed_at, checkpoint_score, module_checkpoint_score)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(learner_id, course_id, module_idx, lesson_idx) DO UPDATE SET
            completed_at            = COALESCE(excluded.completed_at,            lesson_records.completed_at),
            checkpoint_score        = COALESCE(excluded.checkpoint_score,        lesson_records.checkpoint_score),
            module_checkpoint_score = COALESCE(excluded.module_checkpoint_score, lesson_records.module_checkpoint_score)
        """
        with self._connect() as con:
            con.execute(sql, (
                r.learner_id, r.course_id, r.module_idx, r.lesson_idx,
                r.started_at, r.completed_at, r.checkpoint_score, r.module_checkpoint_score,
            ))

    def get_lesson_records(self, learner_id: str, course_id: str) -> list[LessonRecord]:
        with self._connect() as con:
            rows = con.execute(
                "SELECT * FROM lesson_records WHERE learner_id=? AND course_id=? "
                "ORDER BY module_idx, lesson_idx",
                (learner_id, course_id),
            ).fetchall()
        return [LessonRecord(**dict(r)) for r in rows]

    # -- Quiz attempts -----------------------------------------------------------

    def insert_quiz_attempt(self, a: QuizAttempt) -> None:
        sql = """
        INSERT OR IGNORE INTO quiz_attempts
            (id, learner_id, course_id, module_idx, lesson_idx, question_id,
             question_text, learner_answer, correct_answer, is_correct,
             topic_tag, quiz_type, attempted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        with self._connect() as con:
            con.execute(sql, (
                a.id, a.learner_id, a.course_id, a.module_idx, a.lesson_idx,
                a.question_id, a.question_text, a.learner_answer, a.correct_answer,
                int(a.is_correct), a.topic_tag, a.quiz_type, a.attempted_at,
            ))

    # -- Weak topics -------------------------------------------------------------

    def update_weak_topic(
        self, learner_id: str, course_id: str, topic: str, is_correct: bool
    ) -> None:
        miss = 0 if is_correct else 1
        now  = time.time()
        sql = """
        INSERT INTO weak_topics (learner_id, course_id, topic, miss_count, total_count, last_seen_at)
        VALUES (?, ?, ?, ?, 1, ?)
        ON CONFLICT(learner_id, course_id, topic) DO UPDATE SET
            miss_count  = miss_count  + ?,
            total_count = total_count + 1,
            last_seen_at = ?
        """
        with self._connect() as con:
            con.execute(sql, (learner_id, course_id, topic, miss, now, miss, now))

    def get_weak_topics(self, learner_id: str, course_id: str) -> list[WeakTopic]:
        with self._connect() as con:
            rows = con.execute(
                "SELECT * FROM weak_topics WHERE learner_id=? AND course_id=? "
                "ORDER BY CAST(miss_count AS REAL) / MAX(total_count, 1) DESC, total_count DESC",
                (learner_id, course_id),
            ).fetchall()
        return [WeakTopic(**dict(r)) for r in rows]
