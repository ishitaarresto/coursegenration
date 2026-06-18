"""
api/notification_store.py

Thin helper that any part of the backend can import to create a notification
without coupling to the router or knowing about sessions.

Usage:
    from api.notification_store import push
    push('admin', 'Course Ready', 'My Course generated OK.', icon='🤖', notif_type='course_generated')
    push(learner_id, 'Certificate Earned', 'You passed!', icon='🎓', notif_type='certificate_earned')
"""
from __future__ import annotations

import logging
import time
import uuid

logger = logging.getLogger("arresto.notifications")


def push(
    recipient_id: str,
    title: str,
    body: str,
    icon: str = "🔔",
    notif_type: str = "system",
) -> None:
    """Insert one notification row. Silently swallows errors so callers never fail."""
    try:
        from api.db import SessionLocal
        from api.models.notifications import NotificationRow

        with SessionLocal() as db:
            db.add(
                NotificationRow(
                    id=str(uuid.uuid4()),
                    recipient_id=recipient_id,
                    title=title,
                    body=body,
                    icon=icon,
                    notif_type=notif_type,
                    read=0,
                    created_at=time.time(),
                )
            )
            db.commit()
    except Exception as exc:
        logger.warning("Could not push notification to '%s': %s", recipient_id, exc)
