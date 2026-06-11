"""Text-to-Speech via edge-tts — free, 70+ languages, Microsoft neural voices.

Adapted from LMSarresto. Handles long texts by chunking at sentence boundaries
and concatenating with ffmpeg. Supports Devanagari / Hindi sentence boundaries
(uses the dandā '।' as a split point alongside standard punctuation).
"""
from __future__ import annotations

import asyncio
import re
from pathlib import Path

import edge_tts

LANGUAGE_VOICES: dict[str, str] = {
    # Global
    "en":    "en-US-AriaNeural",
    "en-gb": "en-GB-SoniaNeural",
    "en-in": "en-IN-NeerjaNeural",
    "es":    "es-ES-ElviraNeural",
    "es-mx": "es-MX-DaliaNeural",
    "fr":    "fr-FR-DeniseNeural",
    "de":    "de-DE-KatjaNeural",
    "ar":    "ar-SA-ZariyahNeural",
    "zh":    "zh-CN-XiaoxiaoNeural",
    "ja":    "ja-JP-NanamiNeural",
    "ko":    "ko-KR-SunHiNeural",
    "pt":    "pt-BR-FranciscaNeural",
    "it":    "it-IT-ElsaNeural",
    "nl":    "nl-NL-ColetteNeural",
    "tr":    "tr-TR-EmelNeural",
    "ru":    "ru-RU-SvetlanaNeural",
    "pl":    "pl-PL-AgnieszkaNeural",
    "id":    "id-ID-GadisNeural",
    "ms":    "ms-MY-YasminNeural",
    # Indian — edge-tts voices (used when SARVAM_API_KEY not set)
    "hi":    "hi-IN-SwaraNeural",
    "ta":    "ta-IN-PallaviNeural",
    "te":    "te-IN-ShrutiNeural",
    "bn":    "bn-IN-TanishaaNeural",
    "gu":    "gu-IN-DhwaniNeural",
    "kn":    "kn-IN-SapnaNeural",
    "ml":    "ml-IN-SobhanaNeural",
    "mr":    "mr-IN-AarohiNeural",
}

# pa (Punjabi) and od (Odia) have no edge-tts voice — Sarvam required
_SARVAM_ONLY_LANGS = ["pa", "od"]
SUPPORTED_LANGUAGES = list(LANGUAGE_VOICES.keys()) + _SARVAM_ONLY_LANGS

_MAX_CHUNK_WORDS = 400


def get_voice(lang: str) -> str:
    return LANGUAGE_VOICES.get(lang.lower(), LANGUAGE_VOICES["en"])


def _chunk_text(text: str) -> list[str]:
    sentences = re.split(r"(?<=[.!?।])\s+", text.strip())
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
    for attempt in range(3):
        try:
            communicate = edge_tts.Communicate(text, voice)
            await communicate.save(str(output_path))
            if output_path.exists() and output_path.stat().st_size > 512:
                return
        except Exception:
            if attempt == 2:
                raise
        await asyncio.sleep(1)
    raise RuntimeError(f"edge-tts produced no audio after 3 attempts: {text[:80]}")


async def _synthesise(text: str, voice: str, output_path: Path) -> None:
    import subprocess, shutil
    from modules.video.generators.video import _ffmpeg

    chunks = _chunk_text(text)
    if len(chunks) == 1:
        await _synthesise_chunk(text, voice, output_path)
        return

    tmp_dir = output_path.parent / "_tts_chunks"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    parts: list[Path] = []
    for i, chunk in enumerate(chunks):
        part = tmp_dir / f"part_{i:03d}.mp3"
        await _synthesise_chunk(chunk, voice, part)
        parts.append(part)

    list_file = tmp_dir / "list.txt"
    list_file.write_text("\n".join(f"file '{p.resolve()}'" for p in parts), encoding="utf-8")
    subprocess.run([
        _ffmpeg(), "-y", "-f", "concat", "-safe", "0",
        "-i", str(list_file), "-c", "copy", str(output_path),
    ], check=True, capture_output=True)
    shutil.rmtree(tmp_dir, ignore_errors=True)


def synthesise(text: str, lang: str, output_path: Path) -> Path:
    """Synchronous TTS → MP3. Returns the output path."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    voice = get_voice(lang)
    asyncio.run(_synthesise(text, voice, output_path))
    return output_path


async def _synth_chunk_with_timings(
    text: str, voice: str, output_path: Path, time_offset: float = 0.0
) -> list[dict]:
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


async def _synth_with_timings(text: str, voice: str, output_path: Path) -> list[dict]:
    import subprocess, shutil
    from modules.video.generators.video import _ffmpeg, _ffprobe

    chunks = _chunk_text(text)
    if len(chunks) == 1:
        return await _synth_chunk_with_timings(text, voice, output_path)

    tmp_dir = output_path.parent / "_tts_chunks"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    all_words: list[dict] = []
    parts: list[Path] = []
    time_cursor = 0.0

    for i, chunk in enumerate(chunks):
        part = tmp_dir / f"part_{i:03d}.mp3"
        words = await _synth_chunk_with_timings(chunk, voice, part, time_offset=time_cursor)
        all_words.extend(words)
        parts.append(part)
        r = subprocess.run(
            [_ffprobe(), "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", str(part)],
            capture_output=True, text=True,
        )
        try:
            time_cursor += float(r.stdout.strip())
        except ValueError:
            time_cursor += len(chunk.split()) / 2.5

    list_file = tmp_dir / "list.txt"
    list_file.write_text("\n".join(f"file '{p.resolve()}'" for p in parts), encoding="utf-8")
    subprocess.run([
        _ffmpeg(), "-y", "-f", "concat", "-safe", "0",
        "-i", str(list_file), "-c", "copy", str(output_path),
    ], check=True, capture_output=True)
    shutil.rmtree(tmp_dir, ignore_errors=True)
    return all_words


def synthesise_with_timings(text: str, lang: str, output_path: Path) -> list[dict]:
    """Sync TTS → MP3 + per-word timings [{word, start, end}]."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    voice = get_voice(lang)
    return asyncio.run(_synth_with_timings(text, voice, output_path))
