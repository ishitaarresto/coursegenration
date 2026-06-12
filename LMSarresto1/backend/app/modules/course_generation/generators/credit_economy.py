"""HeyGen credit-economy system.

Goal: produce a high-quality HeyGen video while consuming as FEW credits as possible.

HeyGen Video Agent charges by OUTPUT VIDEO LENGTH. The single biggest lever is how
long the generated video is — which is driven by how much narration we feed it. So
the strategy is:

    1. CAP the narration to a credit budget (condense, never pad).
    2. ESTIMATE the credit cost before spending anything.
    3. PRE-FLIGHT the balance so we never fire a render we can't afford.
    4. CACHE finished videos so the same lesson never costs twice.

Quality is preserved by condensing intelligently (keep the punchy, concrete teaching
lines; drop filler, repetition, and rhetorical padding) rather than truncating.
"""
from __future__ import annotations

# ── Cost model ───────────────────────────────────────────────────────────────
# HeyGen Video Agent v3: roughly ~1 credit per ~6 seconds of finished video, and
# spoken narration runs ~150 words/min (~2.5 words/sec). So:
#   credits ≈ words / (2.5 words/sec * 6 sec/credit) = words / 15
_WORDS_PER_SECOND = 2.5
_SECONDS_PER_CREDIT = 6.0
_WORDS_PER_CREDIT = _WORDS_PER_SECOND * _SECONDS_PER_CREDIT  # = 15

# Economy presets: target spend per render. "lean" is the default — short, sharp video.
ECONOMY_PRESETS = {
    "ultra_lean": 3,   # ~45s video, ~3 credits  — teaser / micro-lesson
    "lean": 6,         # ~90s video, ~6 credits  — recommended default
    "standard": 12,    # ~3min video, ~12 credits — fuller lesson
    "full": 0,         # 0 = no cap (spends whatever the full script needs)
}
DEFAULT_PRESET = "lean"


def estimate_credits(text: str) -> float:
    """Estimate HeyGen credits a narration of this length will cost."""
    words = len(text.split())
    return round(words / _WORDS_PER_CREDIT, 1)


def words_for_budget(credits: int) -> int:
    """Max narration words that fit inside a credit budget."""
    return int(credits * _WORDS_PER_CREDIT)


def condense_for_budget(llm, narration: str, credit_budget: int, *, topic: str = "") -> str:
    """Condense narration so the resulting video fits the credit budget.

    Uses the LLM to keep the most valuable teaching content (concrete facts,
    steps, safety rules, key terms) while cutting filler — preserving quality.
    Falls back to a safe word-trim if the LLM is unavailable.
    """
    if credit_budget <= 0:
        return narration  # "full" preset — no cap

    target_words = words_for_budget(credit_budget)
    current_words = len(narration.split())
    if current_words <= target_words:
        return narration  # already within budget, nothing to cut

    prompt = (
        f"You are condensing a training-video narration to fit a strict length budget "
        f"of about {target_words} words (currently {current_words}).\n\n"
        f"TOPIC: {topic}\n\n"
        "RULES:\n"
        "- Keep ALL concrete facts, numbers, steps, safety rules, and key terms.\n"
        "- Cut filler, repetition, rhetorical questions, and padding.\n"
        "- Keep it natural and spoken — it will be read aloud as narration.\n"
        "- Stay UNDER the word budget. Do not add new information.\n"
        "- Output ONLY the condensed narration text, nothing else.\n\n"
        f"NARRATION TO CONDENSE:\n\"\"\"\n{narration}\n\"\"\""
    )

    try:
        # Use Anthropic directly — the LLMProvider interface only has generate_structured,
        # so we call the raw client for plain-text completion here.
        import anthropic as _anthropic
        from app.core.config import settings as _s
        client = _anthropic.Anthropic(api_key=_s.anthropic_api_key)
        msg = client.messages.create(
            model=_s.llm_model,
            max_tokens=1024,
            messages=[{"role": "user", "content": prompt}],
        )
        out = msg.content[0].text.strip() if msg.content else None
        if out:
            words = out.split()
            if len(words) > target_words * 1.2:
                out = " ".join(words[: int(target_words * 1.2)])
            return out
    except Exception:
        pass

    # Fallback: keep the first N words at a sentence boundary.
    words = narration.split()
    trimmed = " ".join(words[:target_words])
    last_period = trimmed.rfind(".")
    return trimmed[: last_period + 1] if last_period > 0 else trimmed


def plan(narration: str, preset: str = DEFAULT_PRESET) -> dict:
    """Return a credit plan for a render WITHOUT spending anything (for the UI)."""
    budget = ECONOMY_PRESETS.get(preset, ECONOMY_PRESETS[DEFAULT_PRESET])
    full_cost = estimate_credits(narration)
    capped_cost = full_cost if budget == 0 else min(full_cost, budget)
    return {
        "preset": preset,
        "credit_budget": budget,
        "full_script_cost": full_cost,
        "estimated_cost": capped_cost,
        "will_condense": budget > 0 and full_cost > budget,
        "estimated_seconds": round(capped_cost * _SECONDS_PER_CREDIT),
    }
