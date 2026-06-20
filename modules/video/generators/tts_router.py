"""Smart TTS router.

Selects the best available TTS engine per language:

  TTS_PROVIDER=auto    (default)
      Indian languages  → Sarvam Bulbul-v3  (if SARVAM_API_KEY is set)
      Everything else   → edge-tts          (always free, no key needed)

  TTS_PROVIDER=sarvam  → force Sarvam for all languages it supports
  TTS_PROVIDER=edge    → always use edge-tts

All callers import synthesise / synthesise_with_timings from here.
"""
from __future__ import annotations

from pathlib import Path

from api.config import settings


def _use_sarvam(lang: str) -> bool:
    from modules.video.generators.sarvam_tts import SARVAM_SUPPORTED, is_configured
    provider = settings.tts_provider.lower()
    if provider == "edge":
        return False
    if not is_configured():
        return False
    if provider == "sarvam":
        return lang.lower() in SARVAM_SUPPORTED
    # "auto": Sarvam only for Indian languages
    return lang.lower() in SARVAM_SUPPORTED


def synthesise(text: str, lang: str, output_path: Path, voice: str | None = None) -> Path:
    if _use_sarvam(lang):
        from modules.video.generators.sarvam_tts import synthesise as _s
        return _s(text, lang, output_path, speaker=voice or None)
    from modules.video.generators.tts import synthesise as _e
    return _e(text, lang, output_path)


def synthesise_with_timings(text: str, lang: str, output_path: Path, voice: str | None = None) -> list[dict]:
    if _use_sarvam(lang):
        from modules.video.generators.sarvam_tts import synthesise_with_timings as _s
        return _s(text, lang, output_path, speaker=voice or None)
    from modules.video.generators.tts import synthesise_with_timings as _e
    return _e(text, lang, output_path)


def active_engine(lang: str) -> str:
    return "sarvam-bulbul-v3" if _use_sarvam(lang) else "edge-tts"
