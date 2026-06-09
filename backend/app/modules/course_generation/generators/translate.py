"""Translate a narration script into a target language before TTS.

edge-tts (and every other TTS engine) does NOT translate — it only speaks the
text it is given. To get real multilingual narration we must translate the
English script into the target language first, then synthesise with that
language's native voice.

Translation is grounded: the LLM is told to translate faithfully, not to add or
remove information.
"""
from __future__ import annotations

from functools import lru_cache

from pydantic import BaseModel, Field

from app.providers.llm.base import LLMProvider

# Human-readable language names for the translation instruction.
LANGUAGE_NAMES: dict[str, str] = {
    # English variants (no translation needed)
    "en": "English", "en-gb": "English", "en-in": "English",
    # Indian languages (Sarvam)
    "hi": "Hindi", "hi-in": "Hindi",
    "ta": "Tamil", "te": "Telugu",
    "bn": "Bengali", "gu": "Gujarati",
    "kn": "Kannada", "ml": "Malayalam",
    "mr": "Marathi", "pa": "Punjabi", "od": "Odia",
    # International
    "es": "Spanish", "es-mx": "Spanish (Mexican)",
    "fr": "French", "de": "German", "ar": "Arabic",
    "zh": "Simplified Chinese (Mandarin)", "ja": "Japanese", "ko": "Korean",
    "pt": "Brazilian Portuguese", "it": "Italian", "nl": "Dutch",
    "tr": "Turkish", "ru": "Russian", "pl": "Polish",
    "id": "Indonesian", "ms": "Malay",
}

ENGLISH_LANGS = {"en", "en-gb", "en-in"}


def is_english(lang: str) -> bool:
    return lang.lower() in ENGLISH_LANGS


def language_name(lang: str) -> str:
    return LANGUAGE_NAMES.get(lang.lower(), lang)


class _Translation(BaseModel):
    translated_text: str = Field(
        description=(
            "The complete script translated into the target language. Natural, "
            "fluent, and suitable for spoken narration. Preserve meaning, numbers, "
            "units, and proper nouns. Do not add or omit any information."
        )
    )


_SYSTEM = (
    "You are an expert translator specialising in workplace safety-training "
    "narration. You translate faithfully and fluently for spoken delivery, "
    "keeping the tone clear and instructional. You never add, remove, or "
    "editorialise the content."
)


@lru_cache(maxsize=256)
def _cache_key(text: str, lang: str) -> str:  # pragma: no cover - identity helper
    return f"{lang}:{hash(text)}"


def translate_script(llm: LLMProvider, text: str, lang: str) -> str:
    """Translate `text` into `lang`. Returns the original if already English/empty."""
    if not text or not text.strip() or is_english(lang):
        return text

    target = language_name(lang)
    instruction = (
        f"Translate the following safety-training narration script into {target}. "
        "Return ONLY the translation as natural spoken narration — no notes, no "
        "transliteration, no English in parentheses. Keep numbers and units intact."
    )
    result = llm.generate_structured(
        system=_SYSTEM,
        instruction=instruction,
        source_content=text,
        schema=_Translation,
        max_tokens=4096,
    )
    return result.translated_text.strip() or text
