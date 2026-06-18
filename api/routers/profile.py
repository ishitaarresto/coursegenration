"""
api/routers/profile.py

GET   /api/v1/profile/{learner_id}   Learner profile + summary stats
PATCH /api/v1/profile/{learner_id}   Update display name
"""

from __future__ import annotations

import time

from fastapi import APIRouter
from pydantic import BaseModel

from api.db import SessionLocal
from api.models.profile import LearnerProfileRow
from api.models.progress import AssessmentAttemptRow, LessonRecordRow

router = APIRouter(prefix="/api/v1/profile", tags=["Learner Profile"])


class ProfileResponse(BaseModel):
    learner_id:        str
    display_name:      str
    email:             str
    enrolled_courses:  int
    completed_lessons: int
    certificates:      int
    avatar_url:        str | None


class PatchProfileRequest(BaseModel):
    display_name: str | None = None


def _derive_name(learner_id: str) -> str:
    local = learner_id.split("@")[0] if "@" in learner_id else learner_id
    return local.replace(".", " ").replace("_", " ").title()


def _load_profile(learner_id: str) -> ProfileResponse:
    with SessionLocal() as db:
        prof = db.get(LearnerProfileRow, learner_id)
        display_name = (
            prof.display_name
            if prof and prof.display_name
            else _derive_name(learner_id)
        )
        avatar_url = prof.avatar_url if prof else None

        records = (
            db.query(LessonRecordRow)
            .filter(LessonRecordRow.learner_id == learner_id)
            .all()
        )
        enrolled_courses  = len({r.course_id for r in records})
        completed_lessons = sum(1 for r in records if r.completed_at is not None)

        certs = (
            db.query(AssessmentAttemptRow)
            .filter(
                AssessmentAttemptRow.learner_id == learner_id,
                AssessmentAttemptRow.passed == 1,
            )
            .count()
        )

    return ProfileResponse(
        learner_id=learner_id,
        display_name=display_name,
        email=learner_id if "@" in learner_id else "",
        enrolled_courses=enrolled_courses,
        completed_lessons=completed_lessons,
        certificates=certs,
        avatar_url=avatar_url,
    )


@router.get("/{learner_id}", response_model=ProfileResponse)
def get_profile(learner_id: str):
    """Get learner profile + summary stats (enrolled courses, completed lessons, certificates)."""
    return _load_profile(learner_id)


@router.patch("/{learner_id}", response_model=ProfileResponse)
def patch_profile(learner_id: str, body: PatchProfileRequest):
    """Update the learner's display name."""
    with SessionLocal() as db:
        prof = db.get(LearnerProfileRow, learner_id)
        if prof is None:
            prof = LearnerProfileRow(learner_id=learner_id)
            db.add(prof)
        if body.display_name is not None:
            prof.display_name = body.display_name.strip() or None
        prof.updated_at = time.time()
        db.commit()
    return _load_profile(learner_id)
