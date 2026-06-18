"""
api/routers/learners.py -- Admin learner management endpoints.

GET /api/v1/learners             List all learners with summary stats derived from DB
GET /api/v1/learners/{id}        Detail stats for one learner
"""

from __future__ import annotations

import time
from collections import defaultdict

from fastapi import APIRouter
from pydantic import BaseModel

from api.db import SessionLocal
from api.models.profile import LearnerProfileRow
from api.models.progress import AssessmentAttemptRow, LessonRecordRow

router = APIRouter(prefix="/api/v1/learners", tags=["Learner Management"])


# ── Helpers ───────────────────────────────────────────────────────────────────

def _derive_name(learner_id: str) -> str:
    local = learner_id.split("@")[0] if "@" in learner_id else learner_id
    return local.replace(".", " ").replace("_", " ").title()


def _fmt_time(secs: float) -> str:
    h = int(secs // 3600)
    m = int((secs % 3600) // 60)
    if h > 0:
        return f"{h}h {m:02d}m"
    return f"{m}m"


def _fmt_ago(ts: float | None) -> str:
    if ts is None:
        return "Never"
    delta = time.time() - ts
    if delta < 3600:
        mins = max(1, int(delta / 60))
        return f"{mins}m ago"
    if delta < 86400:
        return f"{int(delta / 3600)}h ago"
    return f"{int(delta / 86400)}d ago"


def _status(last_ts: float | None) -> str:
    if last_ts is None:
        return "Inactive"
    return "Active" if (time.time() - last_ts) < 7 * 86400 else "Inactive"


# ── Schemas ───────────────────────────────────────────────────────────────────

class LearnerSummary(BaseModel):
    id:          str
    name:        str
    email:       str
    enrolled:    int
    progress:    int    # 0-100
    last_active: str
    time:        str
    assessments: int
    status:      str


# ── Route helpers ─────────────────────────────────────────────────────────────

def _summarise(
    learner_id: str,
    records: list,
    attempts: list,
    profile: LearnerProfileRow | None,
) -> LearnerSummary:
    name  = (
        profile.display_name if profile and profile.display_name
        else _derive_name(learner_id)
    )
    email = learner_id if "@" in learner_id else ""

    enrolled      = len({r.course_id for r in records})
    total_lessons = len(records)
    completed     = sum(1 for r in records if r.completed_at is not None)
    progress      = int(completed / total_lessons * 100) if total_lessons else 0

    time_secs = sum(
        (r.completed_at - r.started_at)
        for r in records
        if r.completed_at and r.completed_at > r.started_at
    )

    last_ts = max((r.started_at for r in records), default=None)

    return LearnerSummary(
        id=learner_id,
        name=name,
        email=email,
        enrolled=enrolled,
        progress=progress,
        last_active=_fmt_ago(last_ts),
        time=_fmt_time(time_secs),
        assessments=len(attempts),
        status=_status(last_ts),
    )


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("", response_model=list[LearnerSummary])
def list_learners():
    """List every learner who has any activity in the DB, with summary stats."""
    with SessionLocal() as db:
        all_records  = db.query(LessonRecordRow).all()
        all_attempts = db.query(AssessmentAttemptRow).all()
        profiles     = {p.learner_id: p for p in db.query(LearnerProfileRow).all()}

    by_records:  dict[str, list] = defaultdict(list)
    by_attempts: dict[str, list] = defaultdict(list)
    for r in all_records:
        by_records[r.learner_id].append(r)
    for a in all_attempts:
        by_attempts[a.learner_id].append(a)

    learner_ids = sorted(set(by_records) | set(by_attempts))
    results = [
        _summarise(lid, by_records[lid], by_attempts[lid], profiles.get(lid))
        for lid in learner_ids
    ]

    # Active learners first, then alphabetical by name
    return sorted(results, key=lambda l: (l.status != "Active", l.name))


@router.get("/{learner_id}", response_model=LearnerSummary)
def get_learner(learner_id: str):
    """Get summary stats for one learner."""
    with SessionLocal() as db:
        records  = db.query(LessonRecordRow).filter(LessonRecordRow.learner_id == learner_id).all()
        attempts = db.query(AssessmentAttemptRow).filter(AssessmentAttemptRow.learner_id == learner_id).all()
        profile  = db.get(LearnerProfileRow, learner_id)
    return _summarise(learner_id, records, attempts, profile)
