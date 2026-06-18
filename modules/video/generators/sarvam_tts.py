"""Sarvam AI Bulbul-v3 TTS — best-in-class Indian language voices.

Supports: hi, hi-in, ta, te, bn, gu, kn, ml, mr, pa, od, en-in
Chunks long texts at sentence/dandā boundaries and concatenates with ffmpeg.
Mirrors the synthesise() / synthesise_with_timings() interface of tts.py.
"""
from __future__ import annotations

import base64
import io
import subprocess
from pathlib import Path

import httpx

from api.config import settings

SARVAM_VOICES: dict[str, tuple[str, str]] = {
    # Speakers confirmed for Bulbul-v3 (June 2026).
    # Bulbul-v3 speakers are multilingual — lang code selects the language,
    # speaker name selects the voice timbre. Any speaker works with any lang.
    "hi":    ("hi-IN", "ritu"),
    "hi-in": ("hi-IN", "ritu"),
    "ta":    ("ta-IN", "kavitha"),
    "te":    ("te-IN", "gokul"),
    "bn":    ("bn-IN", "priya"),
    "gu":    ("gu-IN", "kavya"),
    "kn":    ("kn-IN", "ishita"),
    "ml":    ("ml-IN", "pooja"),
    "mr":    ("mr-IN", "ritu"),
    "pa":    ("pa-IN", "simran"),
    "od":    ("od-IN", "neha"),
    "en-in": ("en-IN", "rahul"),
}

SARVAM_SUPPORTED = set(SARVAM_VOICES.keys())
MAX_CHARS = 2400


def supports(lang: str) -> bool:
    return lang.lower() in SARVAM_SUPPORTED


def is_configured() -> bool:
    return bool(settings.sarvam_api_key.strip())


def _synth_chunk(text: str, lang_code: str, speaker: str) -> bytes:
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
            "output_audio_codec": "mp3",
        },
        timeout=60.0,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"Sarvam TTS error [{r.status_code}]: {r.text}")
    audios = r.json().get("audios") or []
    if not audios:
        raise RuntimeError(f"Sarvam returned no audio: {r.text}")
    return base64.b64decode(audios[0])


def _chunk_text(text: str, max_chars: int = MAX_CHARS) -> list[str]:
    import re
    sentences = re.split(r"(?<=[।.!?])\s+", text.strip())
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


def _combine_wav_chunks(chunks: list[bytes]) -> bytes:
    if len(chunks) == 1:
        return chunks[0]
    combined = io.BytesIO()
    combined.write(chunks[0])
    for c in chunks[1:]:
        combined.write(c[44:])
    return combined.getvalue()


def _wav_bytes_to_mp3(wav_bytes: bytes, out_path: Path) -> None:
    from modules.video.generators.video import _ffmpeg
    result = subprocess.run(
        [_ffmpeg(), "-y", "-f", "wav", "-i", "pipe:0",
         "-codec:a", "libmp3lame", "-b:a", "128k", str(out_path)],
        input=wav_bytes, capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg wav→mp3 failed: {result.stderr.decode()}")


def synthesise(text: str, lang: str, output_path: Path) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    lang_code, speaker = SARVAM_VOICES[lang.lower()]
    chunks = _chunk_text(text)
    mp3_chunks = [_synth_chunk(c, lang_code, speaker) for c in chunks]
    output_path.write_bytes(b"".join(mp3_chunks))
    return output_path


class SarvamTTSEngine:
    """Drop-in replacement for OpenAI TTSEngine — uses Sarvam Bulbul-v3.

    Exposes synthesize_bytes(text) -> bytes so it is compatible with the
    audio and voice routers without any further changes to those routers.
    """

    def __init__(self, lang: str = "en-in"):
        lang_key = lang.lower()
        self.lang = lang_key if lang_key in SARVAM_SUPPORTED else "en-in"

    def synthesize_bytes(self, text: str) -> bytes:
        lang_code, speaker = SARVAM_VOICES[self.lang]
        chunks = _chunk_text(text)
        return b"".join(_synth_chunk(c, lang_code, speaker) for c in chunks)


def synthesise_with_timings(text: str, lang: str, output_path: Path) -> list[dict]:
    """Synthesise → MP3 and return [{word, start, end}] with proportional timing."""
    import re as _re
    import subprocess as _sp
    from modules.video.generators.video import _ffprobe

    synthesise(text, lang, output_path)
    r = _sp.run(
        [_ffprobe(), "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(output_path)],
        capture_output=True, text=True,
    )
    dur = float(r.stdout.strip() or "20")

    sentence_texts = _re.split(r"(?<=[।.!?])\s+", text.strip())
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
