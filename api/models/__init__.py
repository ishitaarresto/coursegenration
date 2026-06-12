"""
api/models/__init__.py

Importing this package registers every ORM model with the shared Base so that
init_db() → Base.metadata.create_all() picks them all up.
"""

from api.models.jobs import UploadJobRow, CourseJobRow
from api.models.courses import CourseScriptRow
from api.models.sessions import TutorSessionRow
from api.models.renders import VideoRenderRow
from api.models.progress import LessonRecordRow, QuizAttemptRow, WeakTopicRow

__all__ = [
    "UploadJobRow",
    "CourseJobRow",
    "CourseScriptRow",
    "TutorSessionRow",
    "VideoRenderRow",
    "LessonRecordRow",
    "QuizAttemptRow",
    "WeakTopicRow",
]
