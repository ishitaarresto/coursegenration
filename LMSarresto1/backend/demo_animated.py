"""Render ONE lesson as a free animated video. Usage: python demo_animated.py [lesson_id] [style]"""
import sys
from app.core.db import SessionLocal
from app.modules.course_generation import models, schemas
from app.modules.course_generation.generators.animated_render import generate_animated_video

LESSON_ID = int(sys.argv[1]) if len(sys.argv) > 1 else 3
STYLE = sys.argv[2] if len(sys.argv) > 2 else "modern"

db = SessionLocal()
lesson = db.get(models.Lesson, LESSON_ID) or db.query(models.Lesson).first()
print(f"Rendering [{STYLE}] video for lesson {lesson.id}: {lesson.title}")

lc = schemas.LessonContent(
    key_takeaways=lesson.key_takeaways,
    simplified_explanation=lesson.simplified_explanation,
    real_world_examples=lesson.real_world_examples,
    safety_scenarios=[schemas.SafetyScenario(**s) for s in lesson.safety_scenarios],
    summary=lesson.summary,
    narration_script=lesson.narration_script,
)
slides = [schemas.SlideSpec.model_validate(s.payload) for s in lesson.slides]

out = generate_animated_video(lesson.id, lesson.title, lc, slides, lang="en", style=STYLE)
print(f"\nDONE -> {out.resolve()}")
db.close()
