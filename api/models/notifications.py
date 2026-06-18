from __future__ import annotations

from sqlalchemy import Column, Float, Integer, String

from api.db import Base


class NotificationRow(Base):
    __tablename__ = "notifications"

    id           = Column(String, primary_key=True)
    recipient_id = Column(String, nullable=False, index=True)   # learner_id or 'admin'
    title        = Column(String, nullable=False)
    body         = Column(String, nullable=False)
    icon         = Column(String, nullable=False, default="🔔")
    notif_type   = Column(String, nullable=False, default="system")
    read         = Column(Integer, nullable=False, default=0)   # 0 / 1
    created_at   = Column(Float, nullable=False)
