"""Render orchestrators for the HeyGen-backed and Hybrid video styles.

These sit alongside animated_render.py (the free in-house engine). They turn a
lesson into a StyleBrief (style_prompts.build_style_brief) and drive the right
engine:

    animated_scene / whiteboard_doodle  -> HeyGen (paid)
    hybrid                              -> free Claude base + HeyGen premium scenes
    claude_native                       -> delegate to the free whiteboard engine

If HEYGEN_API_KEY is not set, the HeyGen styles raise a clear, user-facing error
and Hybrid degrades gracefully to the free in-house render.
"""
from __future__ import annotations

from pathlib import Path

from app.modules.course_generation import schemas
from app.modules.course_generation.generators import style_prompts
from app.providers.video import heygen_provider


def _lesson_inputs(lesson_title: str, lc: schemas.LessonContent, lang: str = "en") -> dict:
    """Extract topic / narration / emphasis hints, localised to `lang` for narration."""
    from app.modules.course_generation.generators.translate import translate_script
    from app.providers.llm import get_llm

    narration = lc.narration_script or lc.simplified_explanation or lc.summary or lesson_title
    narration = translate_script(get_llm(), narration, lang)
    return {
        "topic": lesson_title,
        "narration": narration,
        "key_points": list(lc.key_takeaways or []),
        "closing_points": list(lc.key_takeaways or [])[:5],
    }


def generate_heygen_video(
    lesson_id: int,
    lesson_title: str,
    lesson_content: schemas.LessonContent,
    style: str,
    lang: str = "en",
    course_type: str = "detailed",
    duration_minutes: int = 15,
    economy: str = "lean",
) -> Path:
    """Render a lesson via HeyGen for the Animated Scene / Whiteboard Doodle styles.

    Credit-economy: the narration is condensed to the `economy` budget, the cost is
    estimated, and we pre-flight the credit balance BEFORE spending anything. A
    cached video for the same (lesson, lang) is reused instead of re-rendering.
    """
    from app.modules.course_generation.generators import credit_economy

    if not heygen_provider.is_configured():
        raise heygen_provider.HeyGenNotConfigured(
            f"The '{style}' style needs a HeyGen API key. Add HEYGEN_API_KEY to "
            "backend/.env, then re-render. (Free styles: Claude Animated.)"
        )

    work = Path("media") / "heygen" / str(lesson_id)
    out = work / f"{lang}.mp4"

    # ── 1. Cache: never pay twice for the same lesson+lang ───────────────────
    if out.exists() and out.stat().st_size > 10_000:
        return out

    inp = _lesson_inputs(lesson_title, lesson_content, lang)

    # ── 2. Condense narration to the credit budget (preserves quality) ───────
    from app.providers.llm import get_llm

    budget = credit_economy.ECONOMY_PRESETS.get(economy, credit_economy.ECONOMY_PRESETS["lean"])
    inp["narration"] = credit_economy.condense_for_budget(
        get_llm(), inp["narration"], budget, topic=lesson_title
    )

    # ── 3. Estimate cost + pre-flight balance BEFORE spending ────────────────
    est = credit_economy.estimate_credits(inp["narration"])
    heygen_provider.preflight(estimated_credits=est)

    brief = style_prompts.build_style_brief(
        style=style,
        course_type=course_type,  # type: ignore[arg-type]
        duration_minutes=duration_minutes,
        **inp,
    )

    heygen_provider.generate(
        brief.engine_prompt,
        title=f"{lesson_title} [{style}]",
        out_path=out,
    )
    return out


def generate_hybrid_video(
    lesson_id: int,
    lesson_title: str,
    lesson_content: schemas.LessonContent,
    lang: str = "en",
    course_type: str = "detailed",
    duration_minutes: int = 15,
    claude_fraction: float = 0.5,
) -> Path:
    """Hybrid render.

    Strategy: the free in-house Claude engine carries the explanatory body of the
    lesson; HeyGen adds premium scenes for high-impact moments. The Hybrid brief is
    built (and stored) regardless, so the cost/quality split is explicit.

    Until HEYGEN_API_KEY is set, this produces the free base video so the feature is
    always usable; once the key is added, premium HeyGen scenes are layered in.
    """
    from app.modules.course_generation.generators.animated_render import (
        generate_whiteboard_video,
    )

    inp = _lesson_inputs(lesson_title, lesson_content, lang)
    brief = style_prompts.build_style_brief(
        style=style_prompts.HYBRID,
        course_type=course_type,  # type: ignore[arg-type]
        duration_minutes=duration_minutes,
        hybrid_claude_fraction=claude_fraction,
        **inp,
    )

    # Free base — always works (this is the in-house whiteboard engine).
    base = generate_whiteboard_video(
        lesson_id=lesson_id,
        lesson_title=lesson_title,
        lesson_content=lesson_content,
        lang=lang,
    )

    if not heygen_provider.is_configured():
        # Graceful degrade: deliver the free base; premium scenes pending key.
        return base

    # ── Premium layer (runs only once the key is added) ──────────────────────
    # Generate a short premium HeyGen demonstration clip and stitch it ahead of
    # the free base. Stitching uses the existing ffmpeg concat helper.
    premium_dir = Path("media") / "hybrid" / str(lesson_id)
    premium = premium_dir / f"{lang}_premium.mp4"
    heygen_provider.generate(
        brief.engine_prompt,
        title=f"{lesson_title} [hybrid-premium]",
        out_path=premium,
    )
    return _concat([premium, base], premium_dir / f"{lang}.mp4")


def _concat(parts: list[Path], out: Path) -> Path:
    """Concatenate MP4 parts (re-encode to a common format for safety)."""
    import subprocess

    from app.modules.course_generation.generators.video import _ffmpeg

    out.parent.mkdir(parents=True, exist_ok=True)
    inputs: list[str] = []
    filters: list[str] = []
    for i, p in enumerate(parts):
        inputs += ["-i", str(p)]
        filters.append(
            f"[{i}:v]scale=1280:720,fps=30,setsar=1[v{i}];[{i}:a]aresample=async=1[a{i}]"
        )
    concat_in = "".join(f"[v{i}][a{i}]" for i in range(len(parts)))
    filter_complex = ";".join(filters) + f";{concat_in}concat=n={len(parts)}:v=1:a=1[v][a]"
    subprocess.run(
        [
            _ffmpeg(), "-y", *inputs,
            "-filter_complex", filter_complex,
            "-map", "[v]", "-map", "[a]",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k",
            str(out),
        ],
        check=True, capture_output=True,
    )
    return out
