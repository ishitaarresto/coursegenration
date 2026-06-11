"""Claude generates a CINEMATIC scene plan + knowledge-check questions.

Two independent LLM calls so questions can NEVER block the video render:
  1. generate_whiteboard_plan() → scenes only (rich animated visuals)
  2. generate_questions()       → MCQ + True/False (returns [] on any failure)

Questions may already be embedded in the script (e.g. "Q: ...  A) ... B) ...")
or absent entirely. The question generator extracts embedded ones when present,
otherwise writes 1-3 fresh ones. If the script has none and none can be written,
it returns an empty list and the video simply has no question cards.
"""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

from modules.video.generators import reference_prompts
from modules.video.generators.llm_provider import LLMProvider


# ── Question models (MCQ + True/False) ─────────────────────────────────────


class Question(BaseModel):
    """One knowledge-check. Either a 4-option MCQ or a True/False statement."""
    kind: Literal["mcq", "true_false"] = Field(
        ..., description="'mcq' = 4 options, one correct. 'true_false' = a statement."
    )
    question: str = Field(..., description=(
        "MCQ: the question. True/False: the statement to judge. "
        "Write in the SAME language as the script."
    ))
    options: list[str] = Field(default_factory=list, description=(
        "MCQ only: exactly 4 options in the script's language. "
        "Leave empty for true_false."
    ))
    correct_index: int = Field(default=0, description=(
        "MCQ: 0-based index of correct option. "
        "True/False: 0 = TRUE is correct, 1 = FALSE is correct."
    ))
    explanation: str = Field(default="", description=(
        "Short explanation shown after answering, in the script's language."
    ))
    after_scene: int = Field(default=0, ge=0, description=(
        "Show this question after scene N (0-based)."
    ))


# ── Scene elements ──────────────────────────────────────────────────────────


class WBElement(BaseModel):
    type: Literal[
        "bullet", "icon", "scenario", "callout",
        "stat", "warning_flash", "key_term", "checklist"
    ] = Field(..., description=(
        "bullet: key point text. "
        "icon: large illustration of a real object/tool. "
        "scenario: split-screen WRONG vs RIGHT comparison. "
        "callout: highlighted tip box. "
        "stat: big number/statistic. "
        "warning_flash: critical red safety warning. "
        "key_term: bold definition box. "
        "checklist: step-by-step list."
    ))
    text: str = Field(default="", description=(
        "Main text. bullet/callout/key_term/warning_flash → the text. "
        "icon → short label. stat → description beside number. "
        "scenario → leave empty. checklist → 'Step 1|Step 2|Step 3'."
    ))
    icon_query: str = Field(default="", description=(
        "ALWAYS IN ENGLISH. Specific Iconify search: 'hard hat construction', "
        "'fire extinguisher red', 'forklift warehouse', 'seatbelt car safety', "
        "'safety harness', 'electrical hazard', 'first aid kit'."
    ))
    stat_value: str = Field(default="", description="stat only: '90%', '3 Steps', '#1 Risk'.")
    wrong_action: str = Field(default="", description="scenario: what NOT to do (❌ red).")
    correct_action: str = Field(default="", description="scenario: the safe action (✅ green).")
    steps: list[str] = Field(default_factory=list, description="checklist: ordered steps.")
    color: str = Field(default="")
    delay: float = Field(default=0.5, ge=0.0, le=12.0)
    emphasis: bool = Field(default=False)


class WBScene(BaseModel):
    script_segment: str = Field(..., description=(
        "EXACT continuous excerpt from the narration this scene covers."
    ))
    accent_color: str = Field(..., description=(
        "Bold hex color, vary strongly across scenes: "
        "#ef4444 red, #f59e0b amber, #22c55e green, #3b82f6 blue, "
        "#8b5cf6 purple, #06b6d4 cyan, #f97316 orange."
    ))
    bg_theme: Literal[
        "dark_road", "dark_construction", "dark_warehouse",
        "dark_industrial", "dark_office", "cinematic_dark"
    ] = Field(..., description=(
        "dark_road: driving. dark_construction: site. dark_warehouse: storage. "
        "dark_industrial: machinery. dark_office: admin. cinematic_dark: generic."
    ))
    title: str = Field(..., description=(
        "Bold scene heading, 2-5 words. In the SAME language as the script."
    ))
    elements: list[WBElement] = Field(
        ..., min_length=3, max_length=7,
        description=(
            "PACK each scene with 3-5 rich visuals (more is better): "
            "Safety scenes → 1 scenario + 1 icon + 1-2 bullets + 1 warning/callout. "
            "Concept scenes → 1 large icon + 2-3 bullets + 1 stat + 1 callout. "
            "Procedure scenes → 1 checklist + 1 icon + 1 callout. "
            "ALWAYS include at least one ICON (real object) per scene. "
            "Space delays progressively (0.3s, 1.0s, 1.8s, 2.6s...)."
        )
    )


class WhiteboardPlan(BaseModel):
    """Scene plan for a lesson video. Contains ONLY scenes — no questions."""
    scenes: list[WBScene] = Field(
        ..., min_length=3, max_length=8,
        description="3-7 scenes covering the COMPLETE narration. Every sentence in one scene."
    )


# ── Scene-plan LLM call ────────────────────────────────────────────────────

_SYSTEM = reference_prompts.CLAUDE_NATIVE + """\

────────────────────────────────────────────────────────────────────────────
HOW TO EXPRESS THE ABOVE VISION IN THIS RENDERER

You do not write free text — you return a structured scene plan. Translate every
directive above into these scene ELEMENTS (this is how the hand-on-whiteboard +
animation hybrid is actually rendered):

  - Whiteboard explanation / abstract idea / definition → "bullet" or "key_term".
  - Action / procedure / steps                          → "checklist" (builds up).
  - Concrete object / tool / machine / PPE              → "icon" of the REAL object.
  - Scenario / safety rule / "do vs don't"             → "scenario" (wrong ❌ vs right ✅).
  - Safety step to highlight                            → "callout" or "warning_flash".
  - Life-critical risk                                  → "warning_flash" (red, dramatic).
  - Number / percentage / count                         → "stat" (big bold value).
  - Example / real situation                            → "icon" + "bullet" mini-scene.

The renderer animates these on a whiteboard-style stage with progressive reveals,
spring-pop icons, split-screen scenarios, and karaoke captions — delivering the
"hand teaching + animation" hybrid described above.

STRUCTURED RULES:
1. Cover the FULL script — every sentence maps to exactly one scene, no gaps.
2. PACK each scene with 3-5 elements; mix whiteboard-style and animated elements.
3. EVERY scene must contain at least one "icon" of a real object/tool/hazard.
4. Every safety rule → a "scenario" (wrong vs right). Every number → a "stat".
   Every procedure → a "checklist". Every life-critical rule → a "warning_flash".
5. icon_query MUST ALWAYS be in ENGLISH, regardless of the script language.
6. ALL other text (titles, bullets, scenarios, callouts, key_terms) MUST be in the
   SAME language as the narration script. Hindi script → Hindi/Devanagari text.
7. Choose a bg_theme matching each scene's environment; vary accent_color strongly.
"""

_ACCENTS = ["#ef4444", "#3b82f6", "#22c55e", "#f59e0b", "#8b5cf6", "#06b6d4", "#f97316"]
_BG_THEMES = [
    "cinematic_dark", "dark_road", "dark_warehouse",
    "dark_construction", "dark_industrial", "dark_office",
]


def _split_sentences(text: str) -> list[str]:
    import re
    parts = re.split(r"(?<=[।.!?])\s+", (text or "").strip())
    return [p.strip() for p in parts if p.strip()]


def _fallback_plan(script: str, lesson_title: str) -> WhiteboardPlan:
    """Deterministically build a VALID scene plan from the raw script.

    Used when the LLM returns an empty/invalid plan. Guarantees the video render
    never crashes — every lesson always produces a watchable animated video.
    """
    sentences = _split_sentences(script) or [lesson_title or "Lesson"]
    n_scenes = max(3, min(6, (len(sentences) + 1) // 2))
    n_scenes = min(n_scenes, len(sentences)) or 1
    per = max(1, -(-len(sentences) // n_scenes))  # ceil division

    scenes: list[WBScene] = []
    for i in range(0, len(sentences), per):
        chunk = sentences[i : i + per]
        idx = len(scenes)
        title_words = chunk[0].split()[:4]
        title = " ".join(title_words) or f"Part {idx + 1}"

        elements: list[WBElement] = [
            WBElement(type="icon", text=title[:20],
                      icon_query="safety training shield checklist", delay=0.3),
        ]
        for j, sent in enumerate(chunk[:4]):
            elements.append(WBElement(type="bullet", text=sent, delay=1.0 + j * 0.9))

        while len(elements) < 3:
            elements.append(
                WBElement(type="callout", text=chunk[-1] if chunk else title,
                          delay=1.0 + len(elements) * 0.9)
            )

        scenes.append(WBScene(
            script_segment=" ".join(chunk),
            accent_color=_ACCENTS[idx % len(_ACCENTS)],
            bg_theme=_BG_THEMES[idx % len(_BG_THEMES)],
            title=title,
            elements=elements[:7],
        ))

    while len(scenes) < 3:
        idx = len(scenes)
        scenes.append(WBScene(
            script_segment=lesson_title or "Summary",
            accent_color=_ACCENTS[idx % len(_ACCENTS)],
            bg_theme="cinematic_dark",
            title=(lesson_title or "Summary")[:24],
            elements=[
                WBElement(type="icon", text="Recap",
                          icon_query="checklist summary", delay=0.3),
                WBElement(type="bullet", text=lesson_title or "Key points", delay=1.0),
                WBElement(type="callout", text="Review the key safety points.", delay=1.9),
            ],
        ))
    return WhiteboardPlan(scenes=scenes)


def generate_whiteboard_plan(
    llm: LLMProvider, script: str, lesson_title: str
) -> WhiteboardPlan:
    """Plan cinematic, animation-dense scenes. NEVER raises — falls back if the LLM fails."""
    instruction = (
        f"LESSON: {lesson_title}\n\n"
        f"SCRIPT (cover every sentence — no gaps):\n{script}\n\n"
        "Create a cinematic, animation-DENSE safety training scene plan with 3-7 scenes. "
        "You MUST return a non-empty 'scenes' array. "
        "Pack every scene with multiple animated elements — icons of real objects, "
        "wrong-vs-right scenarios, stats, warnings, checklists. "
        "Every scene needs at least one object ICON. "
        "Write ALL text in the SAME language as the script above. "
        "icon_query fields must always be in English."
    )

    for _attempt in range(2):
        try:
            plan = llm.generate_structured(
                system=_SYSTEM,
                instruction=instruction,
                source_content=script,
                schema=WhiteboardPlan,
                max_tokens=7000,
            )
            if plan and plan.scenes:
                return plan
        except Exception:
            pass

    return _fallback_plan(script, lesson_title)


# ── Question generation (separate, never blocks the render) ────────────────


class _QuestionPlan(BaseModel):
    questions: list[Question] = Field(default_factory=list)


_Q_SYSTEM = """\
You create knowledge-check questions for a safety training lesson.

You support TWO kinds:
  - "mcq": a question with EXACTLY 4 options, one correct (correct_index 0-3).
  - "true_false": a statement to judge. correct_index 0 = TRUE, 1 = FALSE.

If the SCRIPT already contains embedded questions (e.g. "Q: ...", "True or False: ...",
"A) ... B) ..."), EXTRACT and structure those exactly. Otherwise, WRITE 1-3 fresh
questions testing the most important facts.

Write every question, option, and explanation in the SAME language as the script.
Spread questions across the lesson using after_scene (0-based).
If the script is too short or has no testable facts, return an empty list.
"""


def generate_questions(
    llm: LLMProvider, script: str, num_scenes: int
) -> list[Question]:
    """Extract embedded questions or generate fresh MCQ/True-False. [] on any failure."""
    try:
        instruction = (
            f"The lesson video has {num_scenes} scenes (0-indexed).\n\n"
            f"SCRIPT:\n{script}\n\n"
            "Produce knowledge-check questions (mcq and/or true_false). "
            "Extract any embedded in the script; otherwise write 1-3 good ones. "
            "Each mcq has exactly 4 options. Write everything in the script's language. "
            "Set after_scene to spread them across the lesson."
        )
        result = llm.generate_structured(
            system=_Q_SYSTEM,
            instruction=instruction,
            source_content=script,
            schema=_QuestionPlan,
            max_tokens=2000,
        )
        clean: list[Question] = []
        for q in (result.questions or []):
            try:
                if q.kind == "mcq":
                    if len(q.options) != 4:
                        continue
                    q.correct_index = max(0, min(3, q.correct_index))
                else:
                    q.options = []
                    q.correct_index = 0 if q.correct_index == 0 else 1
                q.after_scene = max(0, min(num_scenes - 1, q.after_scene))
                clean.append(q)
            except Exception:
                continue
        return clean
    except Exception:
        return []
