"""
api/routers/notifications.py

GET    /api/v1/notifications              List notifications for a recipient
PATCH  /api/v1/notifications/{id}/read   Mark one notification as read
PATCH  /api/v1/notifications/read-all    Mark all notifications read for a recipient
"""
from __future__ import annotations

import time

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import desc

router = APIRouter(prefix="/api/v1/notifications", tags=["Notifications"])


def _ago(ts: float) -> str:
    diff = time.time() - ts
    if diff < 60:
        return "just now"
    if diff < 3600:
        return f"{int(diff / 60)}m ago"
    if diff < 86400:
        return f"{int(diff / 3600)}h ago"
    return f"{int(diff / 86400)}d ago"


def _row_to_dict(r) -> dict:
    return {
        "id":         r.id,
        "title":      r.title,
        "body":       r.body,
        "icon":       r.icon,
        "type":       r.notif_type,
        "read":       bool(r.read),
        "time":       _ago(r.created_at),
        "created_at": r.created_at,
    }


@router.get("")
def list_notifications(
    recipient_id: str = Query(..., description="Learner ID or 'admin'"),
):
    """Return the 50 most recent notifications for this recipient, newest first."""
    from api.db import SessionLocal
    from api.models.notifications import NotificationRow

    with SessionLocal() as db:
        rows = (
            db.query(NotificationRow)
            .filter(NotificationRow.recipient_id == recipient_id)
            .order_by(desc(NotificationRow.created_at))
            .limit(50)
            .all()
        )
        return {
            "notifications": [_row_to_dict(r) for r in rows],
            "unread": sum(1 for r in rows if not r.read),
        }


@router.patch("/read-all")
def mark_all_read(
    recipient_id: str = Query(..., description="Learner ID or 'admin'"),
):
    """Mark every unread notification for this recipient as read."""
    from api.db import SessionLocal
    from api.models.notifications import NotificationRow

    with SessionLocal() as db:
        db.query(NotificationRow).filter(
            NotificationRow.recipient_id == recipient_id,
            NotificationRow.read == 0,
        ).update({"read": 1})
        db.commit()
    return {"ok": True}


@router.patch("/{notif_id}/read")
def mark_one_read(notif_id: str):
    """Mark a single notification as read."""
    from api.db import SessionLocal
    from api.models.notifications import NotificationRow

    with SessionLocal() as db:
        row = db.get(NotificationRow, notif_id)
        if not row:
            raise HTTPException(404, f"Notification '{notif_id}' not found.")
        row.read = 1
        db.commit()
    return {"ok": True}
