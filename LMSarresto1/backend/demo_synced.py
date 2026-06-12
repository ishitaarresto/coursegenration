"""Render a word-synced animated video. Usage: python demo_synced.py [lesson_id] [style]"""
import sys
from app.core.db import SessionLocal
from app.modules.course_generation import models, schemas
from app.modules.course_generation.generators.animated_render import generate_synced_video

LESSON_ID = int(sys.argv[1]) if len(sys.argv) > 1 else 3
STYLE = sys.argv[2] if len(sys.argv) > 2 else "modern"

db = SessionLocal()
lesson = db.get(models.Lesson, LESSON_ID) or db.query(models.Lesson).first()
print(f"Rendering SYNCED [{STYLE}] video for lesson {lesson.id}: {lesson.title}")

lc = schemas.LessonContent(
    key_takeaways=lesson.key_takeaways,
    simplified_explanation=lesson.simplified_explanation,
    real_world_examples=lesson.real_world_examples,
    safety_scenarios=[schemas.SafetyScenario(**s) for s in lesson.safety_scenarios],
    summary=lesson.summary,
    narration_script=lesson.narration_script,
)

out = generate_synced_video(lesson.id, lesson.title, lc, lang="en", style=STYLE)
print(f"\nDONE -> {out.resolve()}")
db.close()
