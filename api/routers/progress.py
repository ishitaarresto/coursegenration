"""
api/routers/progress.py -- Learner progress and adaptive learning route endpoints.

GET  /api/v1/progress/{learner_id}/course/{course_id}   Full progress for a learner on a course
GET  /api/v1/progress/{learner_id}/recommendations      Adaptive learning recommendations
"""

from fastapi import APIRouter, Depends, HTTPException, Query

from api.dependencies import get_progress_tracker
from api.schemas import (
    LearnerProgressResponse,
    LessonRecordItem,
    WeakTopicItem,
    RecommendationItem,
)

router = APIRouter(prefix="/api/v1/progress", tags=["Learner Progress"])


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
