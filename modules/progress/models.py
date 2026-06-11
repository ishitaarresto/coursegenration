"""
modules/progress/models.py -- Data models for learner progress tracking.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field


@dataclass
class QuizAttempt:
    id: str
    learner_id: str
    course_id: str
    module_idx: int
    lesson_idx: int
    question_id: str
    question_text: str
    learner_answer: str
    correct_answer: str
    is_correct: bool
    topic_tag: str
    quiz_type: str   # "manual" | "lesson_checkpoint" | "module_checkpoint"
    attempted_at: float = field(default_factory=time.time)


@dataclass
class LessonRecord:
    learner_id: str
    course_id: str
    module_idx: int
    lesson_idx: int
    started_at: float
    completed_at: float | None = None
    checkpoint_score: float | None = None          # 0.0–1.0
    module_checkpoint_score: float | None = None   # 0.0–1.0


@dataclass
class WeakTopic:
    learner_id: str
    course_id: str
    topic: str
    miss_count: int = 0
    total_count: int = 0
    last_seen_at: float = field(default_factory=time.time)

    @property
    def accuracy(self) -> float:
        if self.total_count == 0:
            return 0.0
        return (self.total_count - self.miss_count) / self.total_count


@dataclass
class LearnerCourseProgress:
    learner_id: str
    course_id: str
    lesson_records: list[LessonRecord]
    weak_topics: list[WeakTopic]

    @property
    def completed_lesson_count(self) -> int:
        return sum(1 for r in self.lesson_records if r.completed_at is not None)

    @property
    def average_checkpoint_score(self) -> float | None:
        scores = [r.checkpoint_score for r in self.lesson_records if r.checkpoint_score is not None]
        return round(sum(scores) / len(scores), 3) if scores else None
