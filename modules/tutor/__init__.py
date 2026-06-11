"""
modules/tutor -- AI Learning Tutor (Learning Buddy)

Public surface:
  TutorSessionStore  -- persists sessions to tutor_sessions.json
  TutorEngine        -- Claude-powered chat, quiz generation, answer evaluation
"""

from modules.tutor.session_store import TutorSessionStore, TutorSession, QuizQuestion
from modules.tutor.tutor_engine  import TutorEngine

__all__ = ["TutorSessionStore", "TutorSession", "QuizQuestion", "TutorEngine"]
