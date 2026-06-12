"""Per-lesson rich content generation."""
from app.modules.course_generation import prompts, schemas
from app.providers.llm.base import LLMProvider


def generate_lesson_content(
    llm: LLMProvider,
    content: str,
    course_title: str,
    module_title: str,
    lesson_title: str,
    objectives: list[str],
) -> schemas.LessonContent:
    instruction = prompts.LESSON_INSTRUCTION.format(
        course_title=course_title,
        module_title=module_title,
        lesson_title=lesson_title,
        objectives="; ".join(objectives) or "(none specified)",
    )
    return llm.generate_structured(
        system=prompts.GROUNDING_SYSTEM,
        instruction=instruction,
        source_content=content,
        schema=schemas.LessonContent,
        max_tokens=3000,
    )
