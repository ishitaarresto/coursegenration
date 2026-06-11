"""
modules/tutor/session_store.py -- AI tutor session store backed by lms.db.

Each session tracks:
  - which course / lesson the learner is on
  - full conversation history (user + assistant turns)
  - pending quiz questions (correct answers stored server-side only)
  - optional embedded course_script

The TutorSession dataclass and QuizQuestion dataclass are unchanged so every
caller (tutor router, progress tracker) requires zero modifications.
"""

from __future__ import annotations

import json
import time
import uuid
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Domain objects (unchanged public interface)
# ---------------------------------------------------------------------------

@dataclass
class QuizQuestion:
    question_id:    str
    question:       str
    options:        list[str]
    correct_answer: str
    explanation:    str
    quiz_type:      str = "manual"
    topic_tag:      str = ""


@dataclass
class TutorSession:
    session_id:      str
    source_file:     str
    course_title:    str
    target_audience: str
    current_module:  int
    current_lesson:  int
    history:         list[dict]         = field(default_factory=list)
    course_script:   dict | None        = None
    pending_questions: dict[str, dict]  = field(default_factory=dict)
    created_at:      float              = field(default_factory=time.time)
    updated_at:      float              = field(default_factory=time.time)
    learner_id:                  str    = "anonymous"
    lesson_started_at:           float  = field(default_factory=time.time)
    awaiting_checkpoint:         bool   = False
    checkpoint_type:             str    = ""
    pending_checkpoint_qids:     list   = field(default_factory=list)
    checkpoint_answers:          list   = field(default_factory=list)
    current_lesson_checkpointed: bool   = False
    module_checkpoint_done:      bool   = False

    def get_current_lesson_data(self) -> dict | None:
        if not self.course_script:
            return None
        for mod in self.course_script.get("modules", []):
            if mod["module_number"] == self.current_module:
                for les in mod.get("lessons", []):
                    if les["lesson_number"] == self.current_lesson:
                        return les
        return None

    def get_current_module_data(self) -> dict | None:
        if not self.course_script:
            return None
        for mod in self.course_script.get("modules", []):
            if mod["module_number"] == self.current_module:
                return mod
        return None

    def add_quiz_question(self, q: QuizQuestion) -> None:
        self.pending_questions[q.question_id] = {
            "question_id":    q.question_id,
            "question":       q.question,
            "options":        q.options,
            "correct_answer": q.correct_answer,
            "explanation":    q.explanation,
            "quiz_type":      q.quiz_type,
            "topic_tag":      q.topic_tag,
        }

    def get_quiz_question(self, question_id: str) -> QuizQuestion | None:
        d = self.pending_questions.get(question_id)
        if not d:
            return None
        return QuizQuestion(
            question_id=d["question_id"],
            question=d["question"],
            options=d["options"],
            correct_answer=d["correct_answer"],
            explanation=d["explanation"],
            quiz_type=d.get("quiz_type", "manual"),
            topic_tag=d.get("topic_tag", ""),
        )

    def remove_quiz_question(self, question_id: str) -> None:
        self.pending_questions.pop(question_id, None)


# ---------------------------------------------------------------------------
# Store
# ---------------------------------------------------------------------------

class TutorSessionStore:
    """
    Persists tutor sessions to lms.db via SQLAlchemy.

    An in-memory dict caches active sessions so every chat message does not
    need a DB read.  Writes always go to the DB immediately.
    """

    def __init__(self) -> None:
        self._sessions: dict[str, TutorSession] = {}
        self._load()

    # -- Bootstrap -------------------------------------------------------------

    def _load(self) -> None:
        try:
            from api.db import SessionLocal
            from api.models.sessions import TutorSessionRow
            with SessionLocal() as db:
                for row in db.query(TutorSessionRow).all():
                    self._sessions[row.session_id] = self._row_to_session(row)
        except Exception as exc:
            print(f"[session_store] WARNING: could not load from DB: {exc}")

    # -- Persistence -----------------------------------------------------------

    def _upsert(self, s: TutorSession) -> None:
        """Write (or update) one session to the DB."""
        try:
            from api.db import SessionLocal
            from api.models.sessions import TutorSessionRow
            with SessionLocal() as db:
                row = db.get(TutorSessionRow, s.session_id)
                if row is None:
                    row = TutorSessionRow(session_id=s.session_id)
                    db.add(row)
                row.source_file                   = s.source_file
                row.course_title                  = s.course_title
                row.target_audience               = s.target_audience
                row.learner_id                    = s.learner_id
                row.current_module                = s.current_module
                row.current_lesson                = s.current_lesson
                row.created_at                    = s.created_at
                row.updated_at                    = s.updated_at
                row.lesson_started_at             = s.lesson_started_at
                row.awaiting_checkpoint           = s.awaiting_checkpoint
                row.checkpoint_type               = s.checkpoint_type
                row.current_lesson_checkpointed   = s.current_lesson_checkpointed
                row.module_checkpoint_done        = s.module_checkpoint_done
                row.history_json                  = json.dumps(s.history)
                row.course_script_json            = json.dumps(s.course_script) if s.course_script else None
                row.pending_questions_json        = json.dumps(s.pending_questions)
                row.pending_checkpoint_qids_json  = json.dumps(s.pending_checkpoint_qids)
                row.checkpoint_answers_json       = json.dumps(s.checkpoint_answers)
                db.commit()
        except Exception as exc:
            print(f"[session_store] WARNING: could not persist session: {exc}")

    # -- Public API ------------------------------------------------------------

    def create(
        self,
        source_file:     str,
        course_title:    str,
        target_audience: str,
        current_module:  int = 1,
        current_lesson:  int = 1,
        course_script:   dict | None = None,
        learner_id:      str = "anonymous",
    ) -> TutorSession:
        session = TutorSession(
            session_id=str(uuid.uuid4()),
            source_file=source_file,
            course_title=course_title,
            target_audience=target_audience,
            current_module=current_module,
            current_lesson=current_lesson,
            course_script=course_script,
            learner_id=learner_id,
        )
        self._sessions[session.session_id] = session
        self._upsert(session)
        return session

    def get(self, session_id: str) -> TutorSession | None:
        return self._sessions.get(session_id.strip())

    def save(self) -> None:
        """Persist all in-memory sessions. Called by the tutor router after mutations."""
        for s in self._sessions.values():
            self._upsert(s)

    # -- Internal helpers ------------------------------------------------------

    @staticmethod
    def _row_to_session(row) -> TutorSession:
        return TutorSession(
            session_id=row.session_id,
            source_file=row.source_file,
            course_title=row.course_title,
            target_audience=row.target_audience,
            learner_id=row.learner_id,
            current_module=row.current_module,
            current_lesson=row.current_lesson,
            created_at=row.created_at,
            updated_at=row.updated_at,
            lesson_started_at=row.lesson_started_at or time.time(),
            awaiting_checkpoint=bool(row.awaiting_checkpoint),
            checkpoint_type=row.checkpoint_type or "",
            current_lesson_checkpointed=bool(row.current_lesson_checkpointed),
            module_checkpoint_done=bool(row.module_checkpoint_done),
            history=json.loads(row.history_json) if row.history_json else [],
            course_script=json.loads(row.course_script_json) if row.course_script_json else None,
            pending_questions=json.loads(row.pending_questions_json) if row.pending_questions_json else {},
            pending_checkpoint_qids=json.loads(row.pending_checkpoint_qids_json) if row.pending_checkpoint_qids_json else [],
            checkpoint_answers=json.loads(row.checkpoint_answers_json) if row.checkpoint_answers_json else [],
        )
