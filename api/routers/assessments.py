"""
api/routers/assessments.py

GET /api/v1/assessments/history   All past assessment attempts for a learner
                                  across every course they have taken, newest first.
"""
from __future__ import annotations

from fastapi import APIRouter, Query

router = APIRouter(prefix="/api/v1/assessments", tags=["Assessments"])


@router.get("/history")
def get_assessment_history(
    learner_id: str = Query(..., description="Learner identifier"),
):
    """
    Return all assessment attempts for a learner across all courses, newest first.

    Response shape:
      {
        "attempts": [
          {
            "id":              "<uuid>",
            "course_id":       "<script_id>",
            "course_title":    "Working at Height — Fundamentals",
            "score":           85,
            "correct":         17,
            "total":           20,
            "passed":          true,
            "elapsed_seconds": 1234,
            "taken_at":        1748371200.0,
            "attempt_number":  2,      ← 1-based index for this course (newest = highest)
            "total_attempts":  3       ← total times this course was attempted
          },
          …
        ],
        "total": 12
      }
    """
    from collections import Counter

    from sqlalchemy import desc

    from api.db import SessionLocal
    from api.models.courses import CourseScriptRow
    from api.models.progress import AssessmentAttemptRow

    with SessionLocal() as db:
        rows = (
            db.query(AssessmentAttemptRow)
            .filter(AssessmentAttemptRow.learner_id == learner_id)
            .order_by(desc(AssessmentAttemptRow.taken_at))
            .all()
        )

        if not rows:
            return {"attempts": [], "total": 0}

        # Count total attempts per course
        attempt_counts: Counter[str] = Counter(r.script_id for r in rows)

        # Resolve course titles in one batch (avoid N+1 queries)
        unique_course_ids = list({r.script_id for r in rows})
        title_map: dict[str, str] = {}
        for cid in unique_course_ids:
            script_row = (
                db.query(CourseScriptRow)
                .filter(CourseScriptRow.script_id == cid)
                .first()
            )
            title_map[cid] = script_row.course_title if script_row else cid

        # Assign 1-based attempt numbers per course.
        # Rows are already newest-first, so the first occurrence per course is
        # the latest attempt and gets number = total_attempts.
        course_next_num: dict[str, int] = {}
        result = []
        for r in rows:
            cid = r.script_id
            if cid not in course_next_num:
                course_next_num[cid] = attempt_counts[cid]
            attempt_num = course_next_num[cid]
            course_next_num[cid] -= 1

            result.append(
                {
                    "id":              r.id,
                    "course_id":       cid,
                    "course_title":    title_map.get(cid, cid),
                    "score":           r.score,
                    "correct":         r.correct,
                    "total":           r.total,
                    "passed":          bool(r.passed),
                    "elapsed_seconds": r.elapsed_seconds,
                    "taken_at":        r.taken_at,
                    "attempt_number":  attempt_num,
                    "total_attempts":  attempt_counts[cid],
                }
            )

    return {"attempts": result, "total": len(result)}
