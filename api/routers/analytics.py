"""
api/routers/analytics.py -- Platform-wide analytics overview.

GET /api/v1/analytics/overview
"""

from __future__ import annotations

import time
from collections import defaultdict
from datetime import datetime, timezone

from fastapi import APIRouter
from pydantic import BaseModel

from api.db import SessionLocal
from api.models.courses import CourseScriptRow
from api.models.progress import LessonRecordRow
from api.models.renders import VideoRenderRow

router = APIRouter(prefix="/api/v1/analytics", tags=["Analytics"])

_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
           "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


class MonthlyActivity(BaseModel):
    month: str
    count: int


class OverviewResponse(BaseModel):
    total_courses:      int
    total_videos:       int
    total_learners:     int
    active_learners:    int          # active in the last 30 days
    learner_activity:   list[MonthlyActivity]   # last 6 months
    style_distribution: dict[str, int]


@router.get("/overview", response_model=OverviewResponse)
def get_overview():
    """
    Platform-wide stats: course + video counts, learner headcounts,
    monthly active learners (last 6 months), and video style distribution.
    """
    with SessionLocal() as db:
        total_courses = db.query(CourseScriptRow).count()
        all_records   = db.query(LessonRecordRow).all()
        all_renders   = db.query(VideoRenderRow).all()

    total_videos  = sum(1 for r in all_renders if r.status == "completed")
    learner_ids   = {r.learner_id for r in all_records}
    total_learners = len(learner_ids)

    thirty_ago = time.time() - 30 * 86400
    active_learners = len({r.learner_id for r in all_records if r.started_at >= thirty_ago})

    # Monthly unique active learners for the past 6 months
    now = datetime.now(tz=timezone.utc)
    monthly: dict[str, set[str]] = defaultdict(set)
    for r in all_records:
        dt  = datetime.fromtimestamp(r.started_at, tz=timezone.utc)
        key = _MONTHS[dt.month - 1]
        monthly[key].add(r.learner_id)

    activity: list[MonthlyActivity] = []
    for i in range(5, -1, -1):
        month_idx = (now.month - 1 - i) % 12
        label = _MONTHS[month_idx]
        activity.append(MonthlyActivity(month=label, count=len(monthly.get(label, set()))))

    # Style distribution (completed renders only)
    style_dist: dict[str, int] = defaultdict(int)
    for r in all_renders:
        if r.status == "completed":
            style_dist[r.style] += 1

    return OverviewResponse(
        total_courses=total_courses,
        total_videos=total_videos,
        total_learners=total_learners,
        active_learners=active_learners,
        learner_activity=activity,
        style_distribution=dict(style_dist),
    )
