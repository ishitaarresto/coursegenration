"""Claude generates a CINEMATIC scene plan from a narration script.

Each scene covers a distinct concept and gets:
  - A dark background theme matching the environment
  - Rich visual elements: objects, scenarios, icons, stats, warnings
  - At least one scenario (correct vs wrong action) for safety content
  - MCQ knowledge checks at natural checkpoints
"""
from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field

from app.providers.llm.base import LLMProvider


# ── MCQ ────────────────────────────────────────────────────────────────────


class MCQQuestion(BaseModel):
    question: str = Field(..., description="Clear, specific question testing the lesson concept.")
    options: list[str] = Field(
        ..., min_length=4, max_length=4,
        description="Exactly 4 options. Only one is correct. Make wrong options plausible."
    )
    correct_index: int = Field(
        ..., ge=0, le=3,
        description="0-based index of the correct option."
    )
    explanation: str = Field(
        ..., description="Brief explanation shown after answering (1-2 sentences)."
    )
    after_scene: int = Field(
        ..., ge=0,
        description="Show this MCQ after scene N completes (0-based scene index)."
    )


# ── Scene elements ──────────────────────────────────────────────────────────


class WBElement(BaseModel):
    type: Literal[
        "bullet", "icon", "scenario", "callout",
        "stat", "warning_flash", "key_term", "checklist"
    ] = Field(..., description=(
        "bullet: key point text. "
        "icon: large centered illustration of a real object/tool. "
        "scenario: split-screen WRONG vs RIGHT action comparison. "
        "callout: highlighted warning/tip box. "
        "stat: big impactful number/statistic. "
        "warning_flash: critical safety warning with red indicator. "
        "key_term: bold definition box. "
        "checklist: step-by-step list with checkmarks."
    ))
    text: str = Field(default="", description=(
        "Main display text. "
        "bullet/callout/key_term/warning_flash → the text. "
        "icon → short label (2-4 words). "
        "stat → description beside the number. "
        "scenario → leave empty (use wrong_action/correct_action). "
        "checklist → pipe-separated steps: 'Step 1|Step 2|Step 3'."
    ))
    icon_query: str = Field(default="", description=(
        "ALWAYS IN ENGLISH. Specific Iconify search: "
        "'hard hat construction worker', 'fire extinguisher red', "
        "'forklift warehouse', 'seatbelt car safety', 'safety harness fall protection', "
        "'electrical hazard warning', 'first aid kit', 'crane hook lifting'. "
        "Be specific — include the object AND context."
    ))
    stat_value: str = Field(default="", description=(
        "For stat type only. The big displayed value: '90%', '3 Steps', '#1 Risk', '22 kN'."
    ))
    wrong_action: str = Field(default="", description=(
        "For scenario type: what NOT to do (shown with ❌ red left panel). Be specific."
    ))
    correct_action: str = Field(default="", description=(
        "For scenario type: the correct safe action (shown with ✅ green right panel). Be specific."
    ))
    steps: list[str] = Field(default_factory=list, description=(
        "For checklist type: list of step strings in order."
    ))
    color: str = Field(default="", description="Hex override. Leave empty to use scene accent.")
    delay: float = Field(default=0.5, ge=0.0, le=12.0, description=(
        "Seconds after scene start when this element animates in. "
        "Icon/warning: 0.2-0.4s. First bullet: 0.8s. Each next: +0.9s. "
        "Stat: 1.0s. Scenario: 0.3s. Callout last: +1.2s after bullets."
    ))
    emphasis: bool = Field(default=False, description="Larger/bolder. Max 1 per scene.")


class WBScene(BaseModel):
    script_segment: str = Field(..., description=(
        "EXACT continuous excerpt from the narration this scene covers. "
        "All scenes together must cover the COMPLETE script with no gaps."
    ))
    accent_color: str = Field(..., description=(
        "Bold scene color (hex). Vary strongly across scenes: "
        "#ef4444 (danger-red), #f59e0b (caution-amber), #22c55e (safe-green), "
        "#3b82f6 (info-blue), #8b5cf6 (purple), #06b6d4 (cyan), #f97316 (orange)."
    ))
    bg_theme: Literal[
        "dark_road", "dark_construction", "dark_warehouse",
        "dark_industrial", "dark_office", "cinematic_dark"
    ] = Field(..., description=(
        "Background environment matching the scene content. "
        "dark_road: road/driving scenes. dark_construction: building/site. "
        "dark_warehouse: storage/forklift. dark_industrial: machinery/factory. "
        "dark_office: admin/rules. cinematic_dark: generic dark gradient."
    ))
    title: str = Field(..., description="Bold scene heading. 2-5 words, active voice, uppercase.")
    elements: list[WBElement] = Field(
        ..., min_length=2, max_length=7,
        description=(
            "REQUIRED mix per scene: "
            "Safety scenes: 1 scenario (wrong vs right) + 1-2 bullets + 1 callout/warning. "
            "Concept scenes: 1 large icon + 2-3 bullets + 1 stat or callout. "
            "Procedure scenes: 1 checklist + 1 icon + 1 callout. "
            "Space delays progressively. First element at 0.2-0.5s."
        )
    )


class WhiteboardPlan(BaseModel):
    scenes: list[WBScene] = Field(
        ..., min_length=3, max_length=8,
        description=(
            "3-7 scenes covering the COMPLETE narration. "
            "Every sentence in exactly one scene. "
            "At least 1 scenario (wrong vs right) element per 2 scenes for safety content."
        )
    )
    mcqs: list[MCQQuestion] = Field(
        ..., min_length=1, max_length=3,
        description=(
            "1-3 MCQ knowledge checks placed at natural concept breaks. "
            "Test specific facts from the narration, not opinions. "
            "Distribute across the lesson (not all at the end)."
        )
    )


# ── LLM call ───────────────────────────────────────────────────────────────

_SYSTEM = """\
You are an expert instructional designer and visual director creating CINEMATIC \
SAFETY TRAINING VIDEOS for an AI-powered LMS platform.

Your output drives a professional animated video renderer that produces:
  - DARK CINEMATIC BACKGROUNDS matching each scene's environment (road, warehouse, site)
  - LARGE ANIMATED OBJECTS that fill the scene (tools, equipment, vehicles, safety gear)
  - SPLIT-SCREEN SCENARIOS showing exactly what NOT to do vs what TO do
  - DRAMATIC STAT CALLOUTS for important numbers and regulations
  - MCQ KNOWLEDGE CHECKS that pause the video and test comprehension

TARGET QUALITY: Think Vyond + Synthesia quality — cinematic, engaging, never static.
This is a SAFETY LMS — every scene must teach through visuals, not just text.

CRITICAL DESIGN RULES:
1. COVER THE FULL SCRIPT — every sentence maps to exactly one scene, no gaps
2. SCENARIO IS KING — for any safety rule, show WRONG action (red) vs CORRECT action (green)
3. OBJECT-FIRST — show the actual tool/equipment/hazard as a large icon, then explain it
4. DARK ENVIRONMENTS — choose bg_theme that matches the scene context
5. BOLD COLORS — red for danger, amber for caution, green for safe, blue for info
6. ICON QUERIES ALWAYS IN ENGLISH — even if narration is in Hindi/Spanish/etc.
7. MCQs TEST FACTS — use specific numbers, procedures, and regulations from the script
8. PROGRESSIVE DELAYS — elements build up 0.7-1.2s apart for dramatic effect
9. CHECKLIST FOR PROCEDURES — use checklist type for any step-by-step process
10. WARNING FLASH FOR CRITICAL HAZARDS — use warning_flash for life-safety rules

ELEMENT SELECTION GUIDE:
- Physical object mentioned → ICON (large, centered)
- Right vs wrong comparison → SCENARIO (split screen)
- Percentage / number / rating → STAT (big impact number)
- Step-by-step process → CHECKLIST
- Critical rule → WARNING_FLASH (red, dramatic)
- Supporting fact → CALLOUT (colored box)
- Key concept → KEY_TERM (definition box)
- Teaching point → BULLET (slide in)
"""


def generate_whiteboard_plan(
    llm: LLMProvider, script: str, lesson_title: str
) -> WhiteboardPlan:
    """Use Claude to plan cinematic animation scenes + MCQs for a narration script."""
    instruction = (
        f"LESSON TITLE: {lesson_title}\n\n"
        f"NARRATION SCRIPT (cover ALL of this — no gaps — every sentence in a scene):\n"
        f"{script}\n\n"
        "Design a CINEMATIC SAFETY TRAINING VIDEO scene plan.\n\n"
        "For each scene:\n"
        "  - Choose a dark bg_theme matching the physical environment described\n"
        "  - Include at least 1 SCENARIO (wrong vs right) element for safety rules\n"
        "  - Include OBJECT ICONS for every tool/equipment/hazard mentioned\n"
        "  - Use WARNING_FLASH for any life-critical safety rule\n"
        "  - Use STAT for any number, percentage, or regulation value\n"
        "  - Use CHECKLIST for any multi-step procedure\n\n"
        "Also generate 1-3 MCQ knowledge checks testing specific facts from the script.\n"
        "Place MCQs at natural concept breaks using after_scene index.\n\n"
        "Make it look like a professional Vyond/Synthesia safety training video."
    )
    return llm.generate_structured(
        system=_SYSTEM,
        instruction=instruction,
        source_content=script,
        schema=WhiteboardPlan,
        max_tokens=6000,
    )
