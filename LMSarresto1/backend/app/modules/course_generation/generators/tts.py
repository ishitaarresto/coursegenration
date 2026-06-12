"""Text-to-Speech via edge-tts — completely FREE, 70+ languages, Microsoft quality.

Voice selection: the LANGUAGE_VOICES dict maps a language code to the best
available neural voice. Add more as needed from `edge-tts --list-voices`.
"""
from __future__ import annotations

import asyncio
import os
from pathlib import Path

import edge_tts

# Best neural voices per language (all free via Microsoft Edge TTS)
LANGUAGE_VOICES: dict[str, str] = {
    "en":    "en-US-AriaNeural",        # English (US) — warm, clear
    "en-gb": "en-GB-SoniaNeural",       # English (UK)
    "en-in": "en-IN-NeerjaNeural",      # English (India)
    "hi":    "hi-IN-SwaraNeural",       # Hindi
    "es":    "es-ES-ElviraNeural",      # Spanish (Spain)
    "es-mx": "es-MX-DaliaNeural",       # Spanish (Mexico)
    "fr":    "fr-FR-DeniseNeural",      # French
    "de":    "de-DE-KatjaNeural",       # German
    "ar":    "ar-SA-ZariyahNeural",     # Arabic
    "zh":    "zh-CN-XiaoxiaoNeural",    # Chinese (Mandarin)
    "ja":    "ja-JP-NanamiNeural",      # Japanese
    "ko":    "ko-KR-SunHiNeural",       # Korean
    "pt":    "pt-BR-FranciscaNeural",   # Portuguese (Brazil)
    "it":    "it-IT-ElsaNeural",        # Italian
    "nl":    "nl-NL-ColetteNeural",     # Dutch
    "tr":    "tr-TR-EmelNeural",        # Turkish
    "ru":    "ru-RU-SvetlanaNeural",    # Russian
    "pl":    "pl-PL-AgnieszkaNeural",   # Polish
    "id":    "id-ID-GadisNeural",       # Indonesian
    "ms":    "ms-MY-YasminNeural",      # Malay
}

# Indian languages handled by Sarvam (added here so the API accepts them)
_SARVAM_ONLY_LANGS = ["ta", "te", "bn", "gu", "kn", "ml", "mr", "pa", "od"]

SUPPORTED_LANGUAGES = list(LANGUAGE_VOICES.keys()) + _SARVAM_ONLY_LANGS


def get_voice(lang: str) -> str:
    """Return best voice for lang code, falling back to English."""
    return LANGUAGE_VOICES.get(lang.lower(), LANGUAGE_VOICES["en"])


# edge-tts silently fails (NoAudioReceived) on texts over ~500 words.
# We chunk at sentence boundaries and concatenate with ffmpeg.
_MAX_CHUNK_WORDS = 400


def _chunk_text(text: str) -> list[str]:
    """Split text into chunks ≤ _MAX_CHUNK_WORDS words, breaking at sentence ends."""
    import re
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    chunks, current, count = [], [], 0
    for s in sentences:
        w = len(s.split())
        if count + w > _MAX_CHUNK_WORDS and current:
            chunks.append(" ".join(current))
            current, count = [], 0
        current.append(s)
        count += w
    if current:
        chunks.append(" ".join(current))
    return chunks or [text]


async def _synthesise_chunk(text: str, voice: str, output_path: Path) -> None:
    """Synthesise a single chunk with retry on NoAudioReceived."""
    for attempt in range(3):
        try:
            communicate = edge_tts.Communicate(text, voice)
            await communicate.save(str(output_path))
            # Verify we actually got audio bytes
            if output_path.exists() and output_path.stat().st_size > 512:
                return
        except Exception:
            if attempt == 2:
                raise
        await asyncio.sleep(1)
    raise RuntimeError(f"edge-tts produced no audio after 3 attempts for: {text[:80]}")


async def _synthesise(text: str, voice: str, output_path: Path) -> None:
    """Synthesise, chunking automatically if the text is long."""
    import subprocess, shutil
    chunks = _chunk_text(text)
    if len(chunks) == 1:
        await _synthesise_chunk(text, voice, output_path)
        return

    # Multiple chunks → synthesise each → concatenate with ffmpeg
    tmp_dir = output_path.parent / "_tts_chunks"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    parts: list[Path] = []
    for i, chunk in enumerate(chunks):
        part = tmp_dir / f"part_{i:03}.mp3"
        await _synthesise_chunk(chunk, voice, part)
        parts.append(part)

    # Build ffmpeg concat list
    list_file = tmp_dir / "list.txt"
    list_file.write_text("\n".join(f"file '{p.resolve()}'" for p in parts), encoding="utf-8")

    from app.modules.course_generation.generators.video import _ffmpeg
    subprocess.run([
        _ffmpeg(), "-y", "-f", "concat", "-safe", "0",
        "-i", str(list_file),
        "-c", "copy", str(output_path),
    ], check=True, capture_output=True)

    shutil.rmtree(tmp_dir, ignore_errors=True)


def synthesise(text: str, lang: str, output_path: Path) -> Path:
    """Synchronous wrapper. Returns path to the generated MP3."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    voice = get_voice(lang)
    asyncio.run(_synthesise(text, voice, output_path))
    return output_path


def audio_dir(lesson_id: int) -> Path:
    base = Path("media") / "audio" / str(lesson_id)
    base.mkdir(parents=True, exist_ok=True)
    return base


import re as _re


async def _synth_chunk_with_timings(text: str, voice: str, output_path: Path, time_offset: float = 0.0) -> list[dict]:
    """Synthesise one chunk and return its word timings shifted by time_offset."""
    communicate = edge_tts.Communicate(text, voice)
    sentences: list[dict] = []
    with open(output_path, "wb") as f:
        async for chunk in communicate.stream():
            t = chunk.get("type")
            if t == "audio":
                f.write(chunk["data"])
            elif t in ("SentenceBoundary", "WordBoundary"):
                sentences.append({
                    "text": chunk["text"],
                    "start": chunk["offset"] / 1e7 + time_offset,
                    "dur": chunk["duration"] / 1e7,
                })
    words: list[dict] = []
    for s in sentences:
        toks = s["text"].split()
        if not toks:
            continue
        total_chars = sum(len(w) for w in toks) or 1
        cursor = s["start"]
        for w in toks:
            span = s["dur"] * (len(w) / total_chars)
            words.append({"word": w, "start": round(cursor, 3), "end": round(cursor + span, 3)})
            cursor += span
    return words


async def _synth_with_timings(text: str, voice: str, output_path: Path):
    """Synthesise audio AND capture per-word timings.

    Automatically chunks long texts (>400 words) to avoid edge-tts NoAudioReceived.
    Timings are offset-corrected so the full word list aligns with the concatenated MP3.
    """
    import subprocess, shutil
    chunks = _chunk_text(text)
    if len(chunks) == 1:
        return await _synth_chunk_with_timings(text, voice, output_path)

    tmp_dir = output_path.parent / "_tts_chunks"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    all_words: list[dict] = []
    parts: list[Path] = []
    time_cursor = 0.0

    for i, chunk in enumerate(chunks):
        part = tmp_dir / f"part_{i:03}.mp3"
        words = await _synth_chunk_with_timings(chunk, voice, part, time_offset=time_cursor)
        all_words.extend(words)
        parts.append(part)
        # Measure this chunk's duration to offset next chunk's timings.
        import subprocess as sp
        from app.modules.course_generation.generators.video import _ffprobe
        r = sp.run([_ffprobe(), "-v", "error", "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1", str(part)],
                   capture_output=True, text=True)
        try:
            time_cursor += float(r.stdout.strip())
        except ValueError:
            time_cursor += len(chunk.split()) / 2.5  # rough fallback

    # Concatenate all parts into the final MP3
    list_file = tmp_dir / "list.txt"
    list_file.write_text("\n".join(f"file '{p.resolve()}'" for p in parts), encoding="utf-8")
    from app.modules.course_generation.generators.video import _ffmpeg
    subprocess.run([
        _ffmpeg(), "-y", "-f", "concat", "-safe", "0",
        "-i", str(list_file), "-c", "copy", str(output_path),
    ], check=True, capture_output=True)

    shutil.rmtree(tmp_dir, ignore_errors=True)
    return all_words


def synthesise_with_timings(text: str, lang: str, output_path: Path) -> list[dict]:
    """Sync wrapper. Returns list of {word, start, end} aligned to the saved MP3."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    voice = get_voice(lang)
    return asyncio.run(_synth_with_timings(text, voice, output_path))
