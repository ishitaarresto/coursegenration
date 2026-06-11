"""
modules/progress/tracker.py -- Business logic for learner progress and recommendations.
"""

from __future__ import annotations

import time
import uuid

from .models import LearnerCourseProgress, LessonRecord, QuizAttempt, WeakTopic
from .store import ProgressStore

_WEAK_THRESHOLD  = 0.6   # accuracy below this = weak topic
_MIN_ATTEMPTS    = 2     # minimum attempts before flagging a topic as weak
_REVIEW_THRESHOLD = 0.6  # lesson checkpoint score below this triggers a "review" recommendation


class ProgressTracker:
    def __init__(self, store: ProgressStore | None = None) -> None:
        self._store = store or ProgressStore()

    # -- Recording ---------------------------------------------------------------

    def record_lesson_start(
        self, learner_id: str, course_id: str, module_idx: int, lesson_idx: int
    ) -> None:
        self._store.upsert_lesson_record(LessonRecord(
            learner_id=learner_id, course_id=course_id,
            module_idx=module_idx, lesson_idx=lesson_idx,
            started_at=time.time(),
        ))

    def record_lesson_checkpoint(
        self,
        learner_id: str,
        course_id: str,
        module_idx: int,
        lesson_idx: int,
        score: float,
    ) -> None:
        self._store.upsert_lesson_record(LessonRecord(
            learner_id=learner_id, course_id=course_id,
            module_idx=module_idx, lesson_idx=lesson_idx,
            started_at=time.time(),   # preserved by COALESCE in upsert
            completed_at=time.time(),
            checkpoint_score=round(score, 3),
        ))

    def record_module_checkpoint(
        self,
        learner_id: str,
        course_id: str,
        module_idx: int,
        score: float,
    ) -> None:
        records = self._store.get_lesson_records(learner_id, course_id)
        for r in records:
            if r.module_idx == module_idx:
                r.module_checkpoint_score = round(score, 3)
                self._store.upsert_lesson_record(r)

    def record_quiz_attempt(
        self,
        *,
        learner_id: str,
        course_id: str,
        module_idx: int,
        lesson_idx: int,
        question_id: str,
        question_text: str,
        learner_answer: str,
        correct_answer: str,
        is_correct: bool,
        topic_tag: str,
        quiz_type: str,
    ) -> None:
        self._store.insert_quiz_attempt(QuizAttempt(
            id=str(uuid.uuid4()),
            learner_id=learner_id, course_id=course_id,
            module_idx=module_idx, lesson_idx=lesson_idx,
            question_id=question_id, question_text=question_text,
            learner_answer=learner_answer, correct_answer=correct_answer,
            is_correct=is_correct, topic_tag=topic_tag, quiz_type=quiz_type,
        ))
        if topic_tag:
            self._store.update_weak_topic(learner_id, course_id, topic_tag, is_correct)

    # -- Queries -----------------------------------------------------------------

    def get_course_progress(self, learner_id: str, course_id: str) -> LearnerCourseProgress:
        return LearnerCourseProgress(
            learner_id=learner_id,
            course_id=course_id,
            lesson_records=self._store.get_lesson_records(learner_id, course_id),
            weak_topics=self._store.get_weak_topics(learner_id, course_id),
        )

    def get_weak_topic_names(
        self, learner_id: str, course_id: str, limit: int = 5
    ) -> list[str]:
        topics = self._store.get_weak_topics(learner_id, course_id)
        return [
            t.topic for t in topics
            if t.total_count >= _MIN_ATTEMPTS and t.accuracy < _WEAK_THRESHOLD
        ][:limit]

    def get_recommendations(self, learner_id: str, course_id: str) -> list[dict]:
        records = self._store.get_lesson_records(learner_id, course_id)
        topics  = self._store.get_weak_topics(learner_id, course_id)
        recs: list[dict] = []

        for r in records:
            if r.checkpoint_score is not None and r.checkpoint_score < _REVIEW_THRESHOLD:
                recs.append({
                    "type":    "review_lesson",
                    "module":  r.module_idx,
                    "lesson":  r.lesson_idx,
                    "score":   r.checkpoint_score,
                    "message": (
                        f"Review Module {r.module_idx}, Lesson {r.lesson_idx} "
                        f"(scored {r.checkpoint_score:.0%})"
                    ),
                })

        for t in topics:
            if t.total_count >= _MIN_ATTEMPTS and t.accuracy < _WEAK_THRESHOLD:
                recs.append({
                    "type":     "weak_topic",
                    "topic":    t.topic,
                    "accuracy": round(t.accuracy, 2),
                    "message":  f"Focus on: '{t.topic}' ({t.accuracy:.0%} accuracy across {t.total_count} questions)",
                })

        return recs
