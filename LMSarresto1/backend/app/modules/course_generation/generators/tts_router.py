"""Smart TTS router.

Picks the best available TTS engine for each language:

    TTS_PROVIDER = "auto"   (default)
        Indian languages  → Sarvam Bulbul v3  (if SARVAM_API_KEY is set)
        Everything else   → edge-tts          (always free)

    TTS_PROVIDER = "sarvam"  → force Sarvam for all langs it supports
    TTS_PROVIDER = "edge"    → always use edge-tts (free, no key needed)

Both engines expose the same interface:
    synthesise(text, lang, output_path)  → Path
    synthesise_with_timings(text, lang, output_path)  → list[{word, start, end}]

All callers should import from here instead of importing tts.py or sarvam_tts.py
directly.
"""
from __future__ import annotations

from pathlib import Path

from app.core.config import settings


def _use_sarvam(lang: str) -> bool:
    from app.modules.course_generation.generators.sarvam_tts import (
        SARVAM_SUPPORTED,
        is_configured,
    )
    provider = settings.tts_provider.lower()
    if provider == "edge":
        return False
    if not is_configured():
        return False
    if provider == "sarvam":
        return lang.lower() in SARVAM_SUPPORTED
    # "auto": use Sarvam for Indian languages only
    return lang.lower() in SARVAM_SUPPORTED


def synthesise(text: str, lang: str, output_path: Path) -> Path:
    if _use_sarvam(lang):
        from app.modules.course_generation.generators.sarvam_tts import (
            synthesise as _s_synth,
        )
        return _s_synth(text, lang, output_path)
    from app.modules.course_generation.generators.tts import (
        synthesise as _e_synth,
    )
    return _e_synth(text, lang, output_path)


def synthesise_with_timings(text: str, lang: str, output_path: Path) -> list[dict]:
    if _use_sarvam(lang):
        from app.modules.course_generation.generators.sarvam_tts import (
            synthesise_with_timings as _s_timings,
        )
        return _s_timings(text, lang, output_path)
    from app.modules.course_generation.generators.tts import (
        synthesise_with_timings as _e_timings,
    )
    return _e_timings(text, lang, output_path)


def active_engine(lang: str) -> str:
    """Return a human-readable name of the engine that will be used."""
    return "sarvam-bulbul-v3" if _use_sarvam(lang) else "edge-tts"
