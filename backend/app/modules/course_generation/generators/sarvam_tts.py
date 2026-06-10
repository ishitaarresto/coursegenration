"""Sarvam AI (Bulbul v3) TTS — best-in-class Indian language voices.

Supports: hi-IN, ta-IN, te-IN, bn-IN, gu-IN, kn-IN, ml-IN, mr-IN, pa-IN, od-IN, en-IN
Returns audio as WAV bytes; we write to disk and derive per-word timings the same
proportional way edge-tts does (Sarvam has no word-boundary stream).

API: POST https://api.sarvam.ai/text-to-speech
Auth: header  api-subscription-key: <key>
Max chars: 2500 per request (we chunk longer scripts automatically).
"""
from __future__ import annotations

import asyncio
import base64
import io
import subprocess
from pathlib import Path

import httpx

from app.core.config import settings

# ── Language + voice mapping ─────────────────────────────────────────────────

# Sarvam language codes → best default speaker for safety-training narration
# Full list: shubh, aditya, ritu, priya, neha, rahul, pooja, rohan, simran,
#            kavya, amit, dev, ishita, shreya, ananya, aryan, meera, vivaan…
SARVAM_VOICES: dict[str, tuple[str, str]] = {
    # (sarvam_lang_code, speaker)
    # bulbul:v3-compatible speakers ONLY (verified against the API):
    # aditya, ritu, ashutosh, priya, neha, rahul, pooja, rohan, simran, kavya,
    # amit, dev, ishita, shreya, ratan, varun, manan, sumit, roopa, kabir,
    # aayan, shubh, advait, anand, tanya, tarun, sunny, mani, gokul, vijay,
    # shruti, suhani, mohit, kavitha, rehan, soham, rupali, niharika
    "hi":    ("hi-IN", "priya"),    # Hindi — clear female instructor
    "hi-in": ("hi-IN", "priya"),
    "ta":    ("ta-IN", "pooja"),    # Tamil
    "te":    ("te-IN", "kavya"),    # Telugu
    "bn":    ("bn-IN", "shreya"),   # Bengali
    "gu":    ("gu-IN", "ishita"),   # Gujarati
    "kn":    ("kn-IN", "roopa"),    # Kannada
    "ml":    ("ml-IN", "niharika"), # Malayalam
    "mr":    ("mr-IN", "ritu"),     # Marathi
    "pa":    ("pa-IN", "simran"),   # Punjabi
    "od":    ("od-IN", "neha"),     # Odia
    "en-in": ("en-IN", "rahul"),    # English (India accent)
}

SARVAM_SUPPORTED = set(SARVAM_VOICES.keys())
MAX_CHARS = 2400   # stay under the 2500-char limit with a small buffer


def supports(lang: str) -> bool:
    return lang.lower() in SARVAM_SUPPORTED


def is_configured() -> bool:
    return bool(settings.sarvam_api_key.strip())


# ── Core HTTP call ────────────────────────────────────────────────────────────

def _synth_chunk(text: str, lang_code: str, speaker: str) -> bytes:
    """Call Sarvam TTS for one chunk; return raw WAV bytes."""
    r = httpx.post(
        f"{settings.sarvam_base_url}/text-to-speech",
        headers={
            "api-subscription-key": settings.sarvam_api_key,
            "Content-Type": "application/json",
        },
        json={
            "text": text,
            "target_language_code": lang_code,
            "speaker": speaker,
            "model": "bulbul:v3",
            "output_audio_codec": "wav",
        },
        timeout=60.0,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"Sarvam TTS error [{r.status_code}]: {r.text}")
    data = r.json()
    # Response: {"audios": ["<base64-wav>"]}
    audios = data.get("audios") or []
    if not audios:
        raise RuntimeError(f"Sarvam returned no audio: {data}")
    return base64.b64decode(audios[0])


def _chunk_text(text: str, max_chars: int = MAX_CHARS) -> list[str]:
    """Split text into chunks at sentence boundaries, each under max_chars."""
    import re
    sentences = re.split(r'(?<=[।.!?])\s+', text.strip())
    chunks, current = [], ""
    for s in sentences:
        if len(current) + len(s) + 1 <= max_chars:
            current = (current + " " + s).strip() if current else s
        else:
            if current:
                chunks.append(current)
            current = s
    if current:
        chunks.append(current)
    return chunks or [text]


def _wav_bytes_to_mp3(wav_bytes: bytes, out_path: Path) -> None:
    """Convert concatenated WAV bytes → MP3 via ffmpeg (same tool already in pipeline)."""
    from app.modules.course_generation.generators.video import _ffmpeg
    result = subprocess.run(
        [_ffmpeg(), "-y", "-f", "wav", "-i", "pipe:0",
         "-codec:a", "libmp3lame", "-b:a", "128k", str(out_path)],
        input=wav_bytes, capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg wav→mp3 failed: {result.stderr.decode()}")


def _combine_wav_chunks(chunks: list[bytes]) -> bytes:
    """Concatenate multiple WAV byte-strings into one (strip headers after first)."""
    if len(chunks) == 1:
        return chunks[0]
    # WAV header is 44 bytes; subsequent chunks skip their header
    combined = io.BytesIO()
    combined.write(chunks[0])
    for c in chunks[1:]:
        combined.write(c[44:])
    return combined.getvalue()


# ── Public API (mirrors edge-tts interface) ───────────────────────────────────

def synthesise(text: str, lang: str, output_path: Path) -> Path:
    """Synthesise speech → MP3 at output_path. Returns path."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    lang_code, speaker = SARVAM_VOICES[lang.lower()]
    chunks = _chunk_text(text)
    wav_chunks = [_synth_chunk(c, lang_code, speaker) for c in chunks]
    wav_combined = _combine_wav_chunks(wav_chunks)
    _wav_bytes_to_mp3(wav_combined, output_path)
    return output_path


def synthesise_with_timings(text: str, lang: str, output_path: Path) -> list[dict]:
    """Synthesise → MP3 and return [{word, start, end}] with proportional timing.

    Sarvam has no word-boundary events, so we derive timing from audio length
    and word character proportions — same approach as edge-tts fallback.
    """
    import re as _re

    from app.modules.course_generation.generators.animated_render import _audio_len

    synthesise(text, lang, output_path)
    dur = _audio_len(output_path)

    # Split into sentences first (rough boundary via punctuation)
    sentence_texts = _re.split(r'(?<=[।.!?])\s+', text.strip())
    total_chars = sum(len(s) for s in sentence_texts) or 1

    words: list[dict] = []
    cursor = 0.0
    for sent in sentence_texts:
        sent_dur = dur * (len(sent) / total_chars)
        toks = sent.split()
        if not toks:
            continue
        sent_chars = sum(len(w) for w in toks) or 1
        for w in toks:
            span = sent_dur * (len(w) / sent_chars)
            words.append({"word": w, "start": round(cursor, 3), "end": round(cursor + span, 3)})
            cursor += span
    return words
