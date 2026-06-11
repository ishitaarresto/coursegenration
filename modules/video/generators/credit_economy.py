"""
modules/video/generators/credit_economy.py -- HeyGen credit cost estimation.

Pure calculation utilities — no API calls, spends nothing.
Used by the cost-preview endpoint to show the user how many credits a render
will cost before they commit to it.

Cost model
----------
HeyGen Video Agent v3 charges ~1 credit per ~6 seconds of finished video.
Spoken narration runs ~2.5 words/second, so:
    credits ≈ words / (2.5 words/sec × 6 sec/credit) = words / 15
"""

from __future__ import annotations

_WORDS_PER_SECOND  = 2.5
_SECONDS_PER_CREDIT = 6.0
_WORDS_PER_CREDIT  = _WORDS_PER_SECOND * _SECONDS_PER_CREDIT  # = 15

ECONOMY_PRESETS: dict[str, int] = {
    "ultra_lean":  3,   # ~45 s video,  ~3 credits  — teaser / micro-lesson
    "lean":        6,   # ~90 s video,  ~6 credits  — recommended default
    "standard":   12,   # ~3 min video, ~12 credits — fuller lesson
    "full":        0,   # 0 = no cap; spends whatever the full script costs
}
DEFAULT_PRESET = "lean"


def estimate_credits(text: str) -> float:
    """Estimate HeyGen credits needed for a narration text."""
    words = len(text.split())
    return round(words / _WORDS_PER_CREDIT, 1)


def words_for_budget(credits: int) -> int:
    """Max narration words that fit inside a credit budget."""
    return int(credits * _WORDS_PER_CREDIT)


def condense_for_budget(narration: str, preset: str, *, topic: str = "") -> str:
    """Condense narration so the resulting video fits the credit budget.

    Uses the LLM to keep the most valuable teaching content (concrete facts,
    steps, safety rules, key terms) while cutting filler — preserving quality.
    Falls back to a safe sentence-boundary trim if the LLM is unavailable.
    """
    budget = ECONOMY_PRESETS.get(preset, ECONOMY_PRESETS[DEFAULT_PRESET])
    if budget <= 0:
        return narration  # "full" preset — no cap

    target_words = words_for_budget(budget)
    current_words = len(narration.split())
    if current_words <= target_words:
        return narration  # already within budget

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
        import anthropic as _anthropic
        from api.config import settings as _s
        client = _anthropic.Anthropic(api_key=_s.anthropic_api_key)
        msg = client.messages.create(
            model=_s.haiku_model,
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

    # Fallback: trim at sentence boundary
    import re
    sentences = re.split(r"(?<=[.!?।])\s+", narration.strip())
    result = []
    word_count = 0
    for sentence in sentences:
        words = len(sentence.split())
        if word_count + words > target_words and result:
            break
        result.append(sentence)
        word_count += words
    return " ".join(result) if result else narration[:target_words * 6]


def plan(narration: str, preset: str = DEFAULT_PRESET) -> dict:
    """
    Return a credit plan for a render WITHOUT spending anything.

    Returns the same shape the cost endpoint sends to the frontend:
        preset, credit_budget, full_script_cost,
        estimated_cost, will_condense, estimated_seconds
    """
    budget     = ECONOMY_PRESETS.get(preset, ECONOMY_PRESETS[DEFAULT_PRESET])
    full_cost  = estimate_credits(narration)
    capped     = full_cost if budget == 0 else min(full_cost, budget)
    return {
        "preset":            preset,
        "credit_budget":     budget,
        "full_script_cost":  full_cost,
        "estimated_cost":    capped,
        "will_condense":     budget > 0 and full_cost > budget,
        "estimated_seconds": round(capped * _SECONDS_PER_CREDIT),
    }
