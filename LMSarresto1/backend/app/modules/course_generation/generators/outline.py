"""Outline generation: source content -> course skeleton (modules + lessons)."""
from app.modules.course_generation import prompts, schemas
from app.providers.llm.base import LLMProvider


def generate_outline(llm: LLMProvider, content: str, mode: str, title_hint: str | None) -> schemas.Outline:
    mode_hint = prompts.QUICK_HINT if mode == "quick" else prompts.DETAILED_HINT
    th = f"- Prefer this course title if it fits the content: {title_hint}\n" if title_hint else ""
    instruction = prompts.OUTLINE_INSTRUCTION.format(mode_hint=mode_hint, title_hint=th)
    return llm.generate_structured(
        system=prompts.GROUNDING_SYSTEM,
        instruction=instruction,
        source_content=content,
        schema=schemas.Outline,
        max_tokens=3000,
    )
