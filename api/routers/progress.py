"""
api/routers/progress.py -- Learner progress and adaptive learning route endpoints.

GET  /api/v1/progress/{learner_id}/course/{course_id}   Full progress for a learner on a course
GET  /api/v1/progress/{learner_id}/recommendations      Adaptive learning recommendations
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

from api.dependencies import get_progress_tracker
from api.schemas import (
    LearnerProgressResponse,
    LessonRecordItem,
    WeakTopicItem,
    RecommendationItem,
)


class _LessonStartRequest(BaseModel):
    module_idx: int
    lesson_idx: int


class _LessonCompleteRequest(BaseModel):
    module_idx: int
    lesson_idx: int
    score: float | None = None  # 0.0–1.0; None = watched without a KC


class _QuizAttemptRequest(BaseModel):
    module_idx:     int
    lesson_idx:     int
    question_id:    str
    question_text:  str = ""
    learner_answer: str = ""
    correct_answer: str = ""
    is_correct:     bool
    topic_tag:      str = ""
    quiz_type:      str = "lesson_checkpoint"

router = APIRouter(prefix="/api/v1/progress", tags=["Learner Progress"])


@router.post("/{learner_id}/course/{course_id}/lesson-start", status_code=204)
def record_lesson_start(
    learner_id: str,
    course_id: str,
    body: _LessonStartRequest,
    progress_tracker=Depends(get_progress_tracker),
):
    """Record that a learner opened a lesson (creates the lesson_records row)."""
    if not progress_tracker:
        raise HTTPException(status_code=503, detail="Progress tracker not initialised.")
    progress_tracker.record_lesson_start(learner_id, course_id, body.module_idx, body.lesson_idx)


@router.post("/{learner_id}/course/{course_id}/lesson-complete", status_code=204)
def record_lesson_complete(
    learner_id: str,
    course_id: str,
    body: _LessonCompleteRequest,
    progress_tracker=Depends(get_progress_tracker),
):
    """
    Mark a lesson as completed.  If `score` is present the lesson had a
    knowledge-check; the score (0.0–1.0) is stored as the checkpoint score
    and used to drive recommendations.  If `score` is absent the lesson was
    watched to the end without a quiz.
    """
    if not progress_tracker:
        raise HTTPException(status_code=503, detail="Progress tracker not initialised.")
    if body.score is not None:
        progress_tracker.record_lesson_checkpoint(
            learner_id, course_id, body.module_idx, body.lesson_idx, body.score
        )
    else:
        progress_tracker.record_lesson_complete(
            learner_id, course_id, body.module_idx, body.lesson_idx
        )


@router.post("/{learner_id}/course/{course_id}/quiz-attempt", status_code=204)
def record_quiz_attempt(
    learner_id: str,
    course_id: str,
    body: _QuizAttemptRequest,
    progress_tracker=Depends(get_progress_tracker),
):
    """
    Record a single KC answer.  Automatically updates the weak-topics table so
    that get_recommendations() can flag topics the learner struggles with.
    """
    if not progress_tracker:
        raise HTTPException(status_code=503, detail="Progress tracker not initialised.")
    progress_tracker.record_quiz_attempt(
        learner_id=learner_id,
        course_id=course_id,
        module_idx=body.module_idx,
        lesson_idx=body.lesson_idx,
        question_id=body.question_id,
        question_text=body.question_text,
        learner_answer=body.learner_answer,
        correct_answer=body.correct_answer,
        is_correct=body.is_correct,
        topic_tag=body.topic_tag or f"m{body.module_idx}l{body.lesson_idx}",
        quiz_type=body.quiz_type,
    )


@router.get("/{learner_id}/course/{course_id}", response_model=LearnerProgressResponse)
def get_course_progress(
    learner_id:       str,
    course_id:        str,
    progress_tracker = Depends(get_progress_tracker),
):
    """
    Full progress summary for a learner on a given course.

    `course_id` is the document's filename as stored in the vector DB
    (same value as `source_file` in the tutor session).
    Includes lesson completion status, quiz scores, weak topics, and recommendations.
    """
    if not progress_tracker:
        raise HTTPException(status_code=503, detail="Progress tracker is not initialised.")

    prog = progress_tracker.get_course_progress(learner_id, course_id)
    recs = progress_tracker.get_recommendations(learner_id, course_id)

    return LearnerProgressResponse(
        learner_id=learner_id,
        course_id=course_id,
        completed_lessons=prog.completed_lesson_count,
        average_checkpoint_score=prog.average_checkpoint_score,
        lesson_records=[
            LessonRecordItem(
                module_idx=r.module_idx,
                lesson_idx=r.lesson_idx,
                started_at=r.started_at,
                completed_at=r.completed_at,
                checkpoint_score=r.checkpoint_score,
                module_checkpoint_score=r.module_checkpoint_score,
            )
            for r in prog.lesson_records
        ],
        weak_topics=[
            WeakTopicItem(
                topic=t.topic,
                accuracy=round(t.accuracy, 2),
                total_attempts=t.total_count,
            )
            for t in prog.weak_topics
        ],
        recommendations=[RecommendationItem(**r) for r in recs],
    )


@router.get("/{learner_id}/recommendations", response_model=list[RecommendationItem])
def get_recommendations(
    learner_id:       str,
    course_id:        str = Query(..., description="Course (source_file) to get recommendations for"),
    progress_tracker = Depends(get_progress_tracker),
):
    """
    Adaptive learning recommendations for a learner.

    Returns a prioritised list of:
    - Lessons to re-study (scored below 60%)
    - Weak topics to focus on (accuracy below 60% across at least 2 questions)
    """
    if not progress_tracker:
        raise HTTPException(status_code=503, detail="Progress tracker is not initialised.")

    recs = progress_tracker.get_recommendations(learner_id, course_id)
    return [RecommendationItem(**r) for r in recs]
