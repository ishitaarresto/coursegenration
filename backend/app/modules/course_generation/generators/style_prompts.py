"""Video STYLE PROMPT engine — Scene-by-Scene JSON master prompt format.

The user pastes a *plain* narration script with NO styling instructions.
They pick:
    1. a STYLE  (how the video should look / which engine renders it)
    2. a COURSE TYPE  (quick = one ~15-min video, detailed = one video per lesson)

This module owns the strong, production-grade master prompts for each style and
assembles the final brief sent to HeyGen / the free Claude engine / a hybrid of both.

Every style prompt instructs the AI to break the script into 5-15 second SCENES and
return a production-ready JSON plan that the rendering pipeline executes directly.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

# ── Style + course-type identifiers ──────────────────────────────────────────

ANIMATED_SCENE = "animated_scene"
WHITEBOARD_DOODLE = "whiteboard_doodle"
CLAUDE_NATIVE = "claude_native"
HYBRID = "hybrid"

Engine = Literal["heygen", "claude", "hybrid"]
CourseType = Literal["quick", "detailed"]


@dataclass
class StyleSpec:
    """Catalog entry shown to the user before generation (drives the UI picker)."""

    key: str
    label: str          # short UI label with emoji
    tagline: str        # one-line description under the label
    engine: Engine      # which renderer produces it
    paid: bool          # True if it consumes the HeyGen wallet
    best_for: str       # guidance for the user
    sample_cost_15min_inr: str  # rough cost for a 15-min course


# Catalog — order = display order in the UI.
STYLE_CATALOG: list[StyleSpec] = [
    StyleSpec(
        key=ANIMATED_SCENE,
        label="🎬 Animated Scene",
        tagline="Rich motion graphics — real objects, equipment, diagrams, scene transitions.",
        engine="heygen",
        paid=True,
        best_for="Flagship courses where you want premium, cinematic teaching visuals.",
        sample_cost_15min_inr="≈ ₹1,275 (HeyGen, 15 min @ ₹85/min)",
    ),
    StyleSpec(
        key=WHITEBOARD_DOODLE,
        label="✍️ Whiteboard Doodle",
        tagline="A real hand draws every concept on a whiteboard, marker style, in real time.",
        engine="heygen",
        paid=True,
        best_for="Instructor-led explainer feel; great for step-by-step procedures.",
        sample_cost_15min_inr="≈ ₹1,275 (HeyGen, 15 min @ ₹85/min)",
    ),
    StyleSpec(
        key=CLAUDE_NATIVE,
        label="🤖 Claude Animated (in-house)",
        tagline="Free in-house engine — animated bullets, icons, question pops, karaoke captions.",
        engine="claude",
        paid=False,
        best_for="High-volume / low-cost courses. Near-zero cost per video.",
        sample_cost_15min_inr="≈ ₹21 (Claude planning only; render is free)",
    ),
    StyleSpec(
        key=HYBRID,
        label="⚡ Hybrid (Claude + HeyGen)",
        tagline="Odd scenes = HeyGen animation · Even scenes = Claude cinematic. Best cost/quality ratio.",
        engine="hybrid",
        paid=True,
        best_for="When you want premium moments without paying premium for the whole video.",
        sample_cost_15min_inr="≈ ₹650 (half free, half HeyGen)",
    ),
]

STYLE_KEYS = [s.key for s in STYLE_CATALOG]
_SPEC_BY_KEY = {s.key: s for s in STYLE_CATALOG}


def get_style_spec(key: str) -> StyleSpec:
    if key not in _SPEC_BY_KEY:
        raise ValueError(f"Unknown style '{key}'. Valid: {STYLE_KEYS}")
    return _SPEC_BY_KEY[key]


# ── The assembled brief returned to the renderer ─────────────────────────────


@dataclass
class StyleBrief:
    style: str
    engine: Engine
    course_type: CourseType
    duration_minutes: int
    engine_prompt: str                     # the full text sent to HeyGen / used by Claude
    claude_fraction: float = 0.0           # for hybrid: share rendered by the free engine
    heygen_fraction: float = 0.0           # for hybrid: share rendered by HeyGen
    notes: list[str] = field(default_factory=list)


# ── Shared building blocks ───────────────────────────────────────────────────

_DEFAULT_AUDIENCE = (
    "Industrial and frontline workers, supervisors, equipment operators, and "
    "safety officers."
)

_NO_AVATAR_RULE = """\
⛔ ABSOLUTE CONSTRAINT — NO AVATAR, NO TALKING HEAD:
Do NOT include any AI avatar, presenter, talking head, or on-screen human narrator.
The video is 100% visual: motion graphics, animations, illustrations, scenes, diagrams,
text overlays, and icons. Narration is handled externally via TTS audio overlay.
Violating this wastes credits and breaks the video format.
"""

_LANG_NAMES = {
    "en": "English", "en-gb": "English", "en-in": "English",
    "hi": "Hindi (Devanagari script)", "ta": "Tamil", "te": "Telugu",
    "bn": "Bengali", "gu": "Gujarati", "kn": "Kannada", "ml": "Malayalam",
    "mr": "Marathi", "pa": "Punjabi", "od": "Odia", "es": "Spanish",
    "fr": "French", "de": "German", "ar": "Arabic", "zh": "Chinese",
    "ja": "Japanese", "ko": "Korean", "pt": "Portuguese", "ru": "Russian",
}


def _lang_directive(lang: str) -> str:
    name = _LANG_NAMES.get(lang.lower(), "the narration language")
    return (
        f"LANGUAGE: The narration is in {name}. ALL on-screen text — titles, labels, "
        f"callouts, captions, key terms — MUST be written in {name} to match the "
        f"narration. Do NOT mix languages on screen."
    )


_UNIVERSAL_RULES = """\
UNIVERSAL RULES (apply to every scene):
- NO AVATAR. NO TALKING HEAD. Zero. Never. (See constraint above.)
- Ground every visual STRICTLY in the narration provided below. Never invent
  facts, statistics, regulations, or procedures that are not in the script.
- Every sentence of narration MUST be supported by a relevant on-screen visual.
- SHOW REAL OBJECTS: every tool, machine, vehicle, PPE item, or hazard named in the
  script must appear as a clear animated object — not an abstract shape or generic icon.
- USE WRONG-vs-RIGHT SCENARIOS for every safety rule: show the unsafe action (red ❌),
  then the correct safe action (green ✅), side by side or in sequence.
- Never leave the screen static for more than a few seconds.
- Never show a plain wall of text.
- Keep on-screen text short (labels, callouts, key terms) — the narration carries detail.
- Use clear, high-contrast, cinematic 2026 corporate-training aesthetics.
- Reinforce safety: correct practice = green indicators; hazards/violations = red indicators.
- If the script contains a question, quiz, or "true or false" prompt, render it as a
  clean on-screen QUESTION CARD with the options listed, then reveal the correct answer.
- End with a concise animated recap / checklist of the lesson's key takeaways.
- NEVER summarize the script — convert EVERY concept into a specific visual.
- Produce final output as structured JSON with one object per scene.
"""

# How to turn each line of narration into a concrete visual. Shared by all styles.
_CONVERSION_LOGIC = """\
HOW TO CONVERT THE SCRIPT INTO VISUALS (apply line by line — every line earns a visual):
- Find the core message of each line, then SHOW it — never narrate over a blank screen.
- Abstract idea / principle / definition → a clear visual metaphor or labelled diagram.
- Action / verb                          → an animated demonstration of that action.
- List / steps / procedure               → an infographic or step-by-step sequence that builds up.
- Example                                → a short mini-scene that plays it out.
- Warning / risk / hazard                → a strong visual alert (red, pulsing, hazard iconography).
- Comparison / "do vs don't"             → a split-screen (wrong ❌ vs right ✅, or before vs after).
- Object / tool / machine / PPE          → show the REAL object, then animate it in use.
- Person / place / environment           → show the person performing the action in that setting.
- Data / number / percentage             → an animated chart, counter, or big stat callout.
Keep pacing fast enough to stay engaging, but never rushed — one clear idea per scene.
"""

# Cinematic transition vocabulary — gives scenes intentional, premium connective tissue.
_TRANSITION_VOCAB = """\
TRANSITIONS (make every style change feel intentional, never abrupt):
- A hand-drawn sketch morphs into the real, fully-rendered object or scene.
- A diagram zooms into a cinematic real-world example.
- A flowchart transforms into a live process animation.
- A whiteboard expands outward into a full environment.
- Use match-cuts, wipes, reveals, and zooms to flow between scenes.
"""

_ANIMATED_SCENE_JSON_SCHEMA = """\
OUTPUT FORMAT — return a JSON array of scene objects, one per 5-15 second scene:
[
  {
    "scene_number": 1,
    "duration_seconds": 10,
    "narration": "exact sentence(s) from the script for this scene",
    "visual_description": "detailed description of every object, character, environment",
    "on_screen_text": "short label / callout / keyword shown on screen",
    "animation_instructions": "how objects move, appear, and transition",
    "camera_movement": "zoom in / pan left / static / pull back / etc."
  }
]
"""

_WHITEBOARD_JSON_SCHEMA = """\
OUTPUT FORMAT — return a JSON array of scene objects, one per 5-15 second scene:
[
  {
    "scene_number": 1,
    "duration_seconds": 10,
    "narration": "exact sentence(s) from the script for this scene",
    "drawing_elements": "objects and diagrams the hand draws",
    "text_written": "handwritten labels, keywords, formulas drawn on the board",
    "animation_sequence": "order in which elements appear, in sync with narration",
    "hand_movements": "rapid sketch / slow careful draw / underline / circle / arrow"
  }
]
"""

_CLAUDE_NATIVE_JSON_SCHEMA = """\
OUTPUT FORMAT — return a JSON array of scene objects, one per 5-15 second scene:
[
  {
    "scene_number": 1,
    "duration_seconds": 10,
    "narration": "exact sentence(s) from the script for this scene",
    "visual_prompt": "cinematic description for AI image / illustration generator",
    "motion_instructions": "how elements animate (slide in, zoom, pulse, etc.)",
    "text_overlays": "educational captions, key terms, bullet points shown",
    "transition": "fade / slide / wipe / zoom into next scene",
    "icon_query": "English search term for the primary icon (ALWAYS in English)"
  }
]
"""

_HYBRID_JSON_SCHEMA = """\
OUTPUT FORMAT — return a JSON array of scene objects, one per 5-15 second scene:
Odd-numbered scenes (1, 3, 5…) use HeyGen animation.
Even-numbered scenes (2, 4, 6…) use Claude cinematic style.
[
  {
    "scene_number": 1,
    "video_engine": "heygen",
    "duration_seconds": 10,
    "narration": "exact sentence(s) from the script for this scene",
    "visual_prompt": "detailed visual/animation description",
    "text_overlay": "short label or key term on screen",
    "animation_instructions": "how objects and graphics move",
    "transition": "seamless transition into next scene"
  }
]
"""


def _fmt_points(points: list[str] | None, bullet: str = "•") -> str:
    if not points:
        return "(derive the key points directly from the narration)"
    return "\n".join(f"  {bullet} {p}" for p in points if p)


def _length_directive(course_type: CourseType, duration_minutes: int) -> str:
    if course_type == "quick":
        return (
            f"COURSE TYPE: QUICK OVERVIEW — one single continuous video of about "
            f"{duration_minutes} minutes covering the whole topic at a brisk pace. "
            "Prioritise the most important points; keep momentum high."
        )
    return (
        "COURSE TYPE: DETAILED LESSON — this is ONE lesson of a multi-lesson course. "
        f"Target about {duration_minutes} minutes for this lesson. Teach this lesson's "
        "concepts thoroughly and in depth; assume other lessons cover the rest."
    )


# ── STYLE 1 — Animated Scene (HeyGen) ────────────────────────────────────────


def _prompt_animated_scene(ctx: "PromptContext") -> str:
    return f"""\
You are an AI Video Director for a professional LMS platform.
Your task: transform the lesson script below into a PREMIUM animated training video.

{_length_directive(ctx.course_type, ctx.duration_minutes)}

TOPIC: "{ctx.topic}"
TARGET AUDIENCE: {ctx.audience}

{_lang_directive(ctx.lang)}

STYLE: Animated Scene (HeyGen)
Goal: A fully-animated, avatar-free training FILM — the polish of a premium animated
explainer. Every important sentence becomes its own visual scene. It must feel like a
cinematic training film, never a slideshow and never a static screen.

{_NO_AVATAR_RULE}
SCENE RULES:
- Break the ENTIRE script into scenes of 5-15 seconds each.
- EVERY concept must be visually represented — never show static content.
- Never show a talking avatar with no supporting visuals.
- Generate animations, icons, illustrations, motion graphics, transitions, labels,
  arrows, diagrams, and explanatory visuals for every scene.
- Turn abstract ideas into visual metaphors; turn actions into animated demonstrations;
  turn lists into infographics; turn examples into mini-scenes; turn warnings into strong
  visual alerts; turn comparisons into split-screen visuals.

{_CONVERSION_LOGIC}
{_TRANSITION_VOCAB}

CONTEXT-AWARE OBJECT GENERATION (pull real objects from the narration):
- Equipment / machinery named → animate that exact equipment in a realistic workplace.
  (cranes, forklifts, hooks, slings, shackles, ropes, chains, conveyors, presses…)
- Measurements / weights / calculations → display objects with animated dimension
  lines, labels, and the calculation appearing on top of the object.
- Fragile / delicate items → show glass, electronics, instruments with cracks/damage
  animating when handled incorrectly.
- Procedures → step-by-step animated walkthrough of each step.
- Hazards → show the hazard scenario, then animate the safe alternative.

VISUAL TOOLKIT (use a varied mix throughout):
object animations · scene transitions · motion graphics · realistic illustrations ·
infographics · animated diagrams · dynamic camera moves · safety-warning animations ·
labels & callouts · before-vs-after comparisons · step-by-step demonstrations ·
red (danger) vs green (safe) indicators.

KEY POINTS TO EMPHASISE:
{_fmt_points(ctx.key_points)}

CLOSING:
{ctx.closing_directive}

VISUAL QUALITY BAR:
Modern 2026 corporate-training look · clean HD · realistic industrial environments ·
smooth motion · consistent visual storytelling · premium paid-course appearance.

{_UNIVERSAL_RULES}

{_ANIMATED_SCENE_JSON_SCHEMA}

NARRATION SCRIPT (narrate verbatim; build a scene for every sentence):
\"\"\"
{ctx.narration}
\"\"\"
"""


# ── STYLE 2 — Whiteboard Doodle (HeyGen) ─────────────────────────────────────


def _prompt_whiteboard_doodle(ctx: "PromptContext") -> str:
    return f"""\
You are an AI Video Director for a professional LMS platform.
Your task: transform the lesson script below into a WHITEBOARD DOODLE training video.

{_length_directive(ctx.course_type, ctx.duration_minutes)}

TOPIC: "{ctx.topic}"
TARGET AUDIENCE: {ctx.audience}

{_lang_directive(ctx.lang)}

STYLE: Whiteboard Doodle (HeyGen)
Goal: A world-class educational documentary taught LIVE through a whiteboard instructor.
A realistic human hand holding a marker is the teacher throughout — drawing, sketching,
highlighting. BUT this is NOT a plain whiteboard animation: whenever the script names a
real object, tool, machine, environment, person, process, or scenario, the whiteboard
naturally TRANSFORMS into rich animated visuals and real-world scenes, then returns to
the board. The viewer should feel taught by a master instructor, never shown slides.

{_NO_AVATAR_RULE}
SCENE RULES:
- Break the ENTIRE script into scenes of 5-15 seconds each.
- A realistic human hand holding a marker appears CONTINUOUSLY as the teacher.
- The hand draws illustrations, diagrams, objects, arrows, labels, and workplace scenes
  in real time, and actively teaches: sketching, highlighting, circling, underlining,
  connecting ideas with arrows, and revealing information step-by-step.
- The hand must NEVER feel random — it always guides the lesson.

DO NOT STAY A SIMPLE WHITEBOARD — TRANSFORM ON CUE (apply to every sentence):
Whatever the narrator names, the hand draws it, then it COMES ALIVE as a real scene.
  • Object / tool / machine → hand sketches it, sketch MORPHS into the real object operating.
  • Measurement / formula → hand draws the object + dimension lines, builds the calculation live.
  • Hazard → hand draws it, the drawing animates into a real failure (cracks, sparks, red alert).
  • Correct method → drawn, then shown as a clean real demonstration with green check marks.
  • Process / list → hand writes a checklist, which expands into a live process animation.
  • Environment / location → the board expands outward into that full environment.

HARD CONSTRAINTS:
- DO NOT make a slideshow.
- DO NOT show static scenes for more than 2 seconds.
- DO NOT show only text.
- DO NOT use generic stock footage.
- DO NOT rely on avatars — the HAND, DRAWINGS, and transformed scenes teach.

{_CONVERSION_LOGIC}
{_TRANSITION_VOCAB}
ANIMATION TOOLKIT:
animated arrows · motion lines · zoom effects · callout boxes · labels · check marks ·
warning icons · comparison graphics · cause-and-effect demonstrations ·
sketch-to-real-scene morphs · diagram-zoom-into-example.

KEY POINTS THE HAND SHOULD DRAW:
{_fmt_points(ctx.key_points)}

CLOSING:
{ctx.closing_directive} — drawn as a hand-written checklist with ticks.

{_UNIVERSAL_RULES}

{_WHITEBOARD_JSON_SCHEMA}

NARRATION SCRIPT (the hand draws every sentence):
\"\"\"
{ctx.narration}
\"\"\"
"""


# ── STYLE 3 — Claude-native (in-house free engine) ───────────────────────────


def _prompt_claude_native(ctx: "PromptContext") -> str:
    return f"""\
You are an AI Video Director for a professional LMS platform.
Your task: transform the lesson script into a premium AI-generated educational video
WITHOUT using HeyGen — using the free in-house Claude rendering engine.

{_length_directive(ctx.course_type, ctx.duration_minutes)}

TOPIC: "{ctx.topic}"
TARGET AUDIENCE: {ctx.audience}

{_lang_directive(ctx.lang)}

STYLE: Claude Native AI Video
Goal: A premium educational film that is a HYBRID of whiteboard teaching and cinematic
animation. A whiteboard instructor's hand guides the lesson — drawing, circling,
underlining, revealing ideas progressively — while rich animated objects, tools,
diagrams, and real-world scenarios appear whenever they help understanding. Mix the two
naturally: whiteboard for abstract ideas, lists, steps, and comparisons; animated scenes
for objects, tools, people, places, actions, procedures, and real situations.

{_NO_AVATAR_RULE}
SCENE RULES:
- Break the ENTIRE script into scenes of 5-15 seconds each.
- Think cinematically — every scene is a composition, not a slide.
- Use the free renderer's strengths: animated bullets, spring-pop icons of real objects,
  bouncing question callouts, big statistic pops, and karaoke captions synced to narration.
- Pick a SPECIFIC, real object icon for each scene (e.g. "safety helmet", "forklift",
  "fire extinguisher") — not generic shapes.
- icon_query MUST ALWAYS be in ENGLISH regardless of the lesson language.
- Add an engaging question_pop per scene where natural ("Can you spot the hazard?").
- Use a stat element whenever the narration gives a number, ratio, or count.
- Whiteboard for abstract/lists/steps/comparisons; animated real-object scenes for
  concrete objects/tools/people/places/actions/procedures. Never force one style.
- End with a recap scene listing key takeaways as a checklist.

{_CONVERSION_LOGIC}
{_TRANSITION_VOCAB}

REQUIREMENTS:
- High visual quality.
- Scene continuity.
- Dynamic educational graphics.
- Concept-driven visuals.
- Strong pacing.

KEY POINTS TO COVER:
{_fmt_points(ctx.key_points)}

CLOSING:
{ctx.closing_directive}

{_UNIVERSAL_RULES}

{_CLAUDE_NATIVE_JSON_SCHEMA}

NARRATION SCRIPT (cover ALL of it — no gaps):
\"\"\"
{ctx.narration}
\"\"\"
"""


# ── STYLE 4 — Hybrid (Claude free scenes + HeyGen premium scenes) ────────────


def _prompt_hybrid(ctx: "PromptContext") -> str:
    return f"""\
You are an AI Video Director for a professional LMS platform.
Your task: create the HIGHEST-QUALITY educational experience by alternating between
HeyGen animated scenes and Claude cinematic scenes throughout the video.

{_length_directive(ctx.course_type, ctx.duration_minutes)}

TOPIC: "{ctx.topic}"
TARGET AUDIENCE: {ctx.audience}

{_lang_directive(ctx.lang)}

STYLE: Hybrid (HeyGen + Claude)
Goal: Seamless alternating video — premium HeyGen animation for impact moments,
Claude cinematic for explanatory/conceptual moments.

{_NO_AVATAR_RULE}

ALTERNATING SCENE RULE:
  Odd scenes  (1, 3, 5, …) → HeyGen Animated Style
  Even scenes (2, 4, 6, …) → Claude Cinematic Style

Example:
  Scene 1 → HeyGen Animation (hazard demonstration in live workplace)
  Scene 2 → Claude Cinematic (definition, diagram, formula breakdown)
  Scene 3 → HeyGen Animation (correct procedure in action)
  Scene 4 → Claude Cinematic (rules and checklist)
  … continue alternating until the lesson ends.

TWO CREATIVE MODES (aim for a ~50/50 split of total runtime):
  HEYGEN MODE → whiteboard teaching: a realistic hand with a marker, hand-drawn
    explanations, labels, arrows, circles, quick sketches, simple animated teaching.
    Best for: definitions, principles, lists, comparisons, step-by-step logic.
  CLAUDE MODE → cinematic animation: real/stylised environments, animated objects,
    tools, people, machines, scenarios, motion graphics, strong visual storytelling.
    Best for: demonstrations, examples, processes, emergencies, actions, real situations.

VISUAL DECISION LOGIC (route each line by its content):
  Abstract idea / definition / principle / comparison / list → HEYGEN MODE.
  Concrete object / tool / place / person / event / procedure / emergency / action → CLAUDE MODE.

ROUTING RULE:
  Live demonstrations, equipment-in-action, hazard/safe comparisons, cinematic intros,
  and the closing → HeyGen.
  Definitions, lists, rules, formulas, step-by-step explanations, recaps → Claude.

{_CONVERSION_LOGIC}
{_TRANSITION_VOCAB}

SCENE RULES:
- Break the ENTIRE script into scenes of 5-15 seconds each.
- Both halves share ONE continuous narration so the video feels seamless.
- HeyGen scenes are generated silent; narration is overlaid in post.
- Maintain seamless transitions, consistent visual identity, typography, and pacing.

KEY POINTS:
{_fmt_points(ctx.key_points)}

CLOSING (render as HeyGen scene for maximum impact):
{ctx.closing_directive}

{_UNIVERSAL_RULES}

{_HYBRID_JSON_SCHEMA}

NARRATION SCRIPT (alternate HeyGen / Claude for every scene):
\"\"\"
{ctx.narration}
\"\"\"
"""


# ── Context + public builder ─────────────────────────────────────────────────


@dataclass
class PromptContext:
    topic: str
    narration: str
    audience: str
    course_type: CourseType
    duration_minutes: int
    key_points: list[str]
    closing_directive: str
    lang: str = "en"


_BUILDERS = {
    ANIMATED_SCENE: _prompt_animated_scene,
    WHITEBOARD_DOODLE: _prompt_whiteboard_doodle,
    CLAUDE_NATIVE: _prompt_claude_native,
    HYBRID: _prompt_hybrid,
}


def build_style_brief(
    *,
    style: str,
    topic: str,
    narration: str,
    key_points: list[str] | None = None,
    closing_points: list[str] | None = None,
    audience: str = _DEFAULT_AUDIENCE,
    course_type: CourseType = "detailed",
    duration_minutes: int = 15,
    hybrid_claude_fraction: float = 0.5,
    lang: str = "en",
) -> StyleBrief:
    """Assemble the final engine prompt + plan for a given style.

    `narration` is the plain pasted/generated script (no styling).
    `key_points` / `closing_points` are optional emphasis hints (e.g. lesson takeaways).
    """
    spec = get_style_spec(style)

    if closing_points:
        closing = "Animated recap checklist:\n" + _fmt_points(closing_points, bullet="✓")
    else:
        closing = (
            "End with an animated recap checklist of this lesson's key takeaways, "
            "then a final reinforcing message."
        )

    ctx = PromptContext(
        topic=topic,
        narration=narration.strip(),
        audience=audience,
        course_type=course_type,
        duration_minutes=duration_minutes,
        key_points=key_points or [],
        closing_directive=closing,
        lang=lang,
    )

    engine_prompt = _BUILDERS[style](ctx)

    brief = StyleBrief(
        style=style,
        engine=spec.engine,
        course_type=course_type,
        duration_minutes=duration_minutes,
        engine_prompt=engine_prompt,
    )

    if spec.engine == "hybrid":
        brief.claude_fraction = max(0.0, min(1.0, hybrid_claude_fraction))
        brief.heygen_fraction = round(1.0 - brief.claude_fraction, 2)
        brief.notes.append(
            f"Odd scenes -> HeyGen ({int(brief.heygen_fraction * 100)}%), "
            f"Even scenes -> Claude ({int(brief.claude_fraction * 100)}%)."
        )
    elif spec.engine == "heygen":
        brief.heygen_fraction = 1.0
        brief.notes.append(f"Estimated cost: {spec.sample_cost_15min_inr}.")
    else:
        brief.claude_fraction = 1.0
        brief.notes.append("Free in-house render.")

    return brief


# ── Reference-prompt-driven crafting (the strong author prompts, used in full) ──


def craft_video_prompt(
    style: str,
    *,
    topic: str,
    narration: str,
    lang: str = "en",
    duration_minutes: int = 15,
    fallback: str = "",
) -> str:
    """Craft a polished, paste-ready video prompt using the full reference prompt.

    The verbatim master reference prompt (reference_prompts.py) is used as the system
    instruction; Claude converts THIS lesson's script into one tailored, production-ready
    generation prompt that fits HeyGen's input limit. On any failure, returns `fallback`
    (the template-built brief) so a render is never blocked.
    """
    from app.modules.course_generation.generators import reference_prompts

    system = reference_prompts.BY_STYLE.get(style)
    if not system:
        return fallback or narration

    lang_name = _LANG_NAMES.get(lang.lower(), "the script's language")
    instruction = (
        f"TOPIC: {topic}\n"
        f"TARGET VIDEO LENGTH: about {duration_minutes} minutes.\n"
        f"NARRATION LANGUAGE: {lang_name} (keep narration and ALL on-screen text in this language).\n\n"
        "Apply everything in your instructions to the SCRIPT below.\n\n"
        "OUTPUT REQUIREMENTS — IMPORTANT:\n"
        "- Output ONLY the final, paste-ready video-generation prompt. No preamble, no\n"
        "  headings, no scene-by-scene breakdown, no commentary.\n"
        "- It must be a single rich descriptive prompt the video engine can use directly.\n"
        "- Keep it UNDER 3500 characters.\n"
        "- Absolutely NO avatar, presenter, or talking head. Voiceover only.\n"
        f"- Write any on-screen text in {lang_name}.\n\n"
        f"SCRIPT:\n\"\"\"\n{narration}\n\"\"\""
    )

    try:
        import anthropic as _anthropic
        from app.core.config import settings as _s

        client = _anthropic.Anthropic(api_key=_s.anthropic_api_key)
        msg = client.messages.create(
            model=_s.llm_model,
            max_tokens=1500,
            system=system,
            messages=[{"role": "user", "content": instruction}],
        )
        out = (msg.content[0].text.strip() if msg.content else "") or ""
        if len(out) >= 80:  # sanity: got a real prompt back
            return out[:3800]
    except Exception:
        pass
    return fallback or narration
