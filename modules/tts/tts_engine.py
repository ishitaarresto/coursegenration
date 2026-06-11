"""
modules/tts/tts_engine.py

Converts lesson narration scripts to MP3 audio using the OpenAI TTS API.

OpenAI TTS has a 4 096-character input limit per request.  Long narrations
are automatically split at sentence boundaries and the resulting MP3 byte
segments are concatenated — no ffmpeg or pydub required since browsers and
most media players resync on MP3 frame headers.
"""

from __future__ import annotations

import re
from pathlib import Path


_MAX_CHUNK_CHARS = 4000


def _split_text(text: str) -> list[str]:
    """Split text into chunks of ≤4000 chars at sentence boundaries."""
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    chunks: list[str] = []
    current = ""
    for sentence in sentences:
        candidate = (current + " " + sentence).strip() if current else sentence
        if len(candidate) <= _MAX_CHUNK_CHARS:
            current = candidate
        else:
            if current:
                chunks.append(current)
            if len(sentence) > _MAX_CHUNK_CHARS:
                # Sentence is itself too long — fall back to word-level splitting
                words = sentence.split()
                current = ""
                for word in words:
                    candidate = (current + " " + word).strip() if current else word
                    if len(candidate) <= _MAX_CHUNK_CHARS:
                        current = candidate
                    else:
                        if current:
                            chunks.append(current)
                        current = word
            else:
                current = sentence
    if current:
        chunks.append(current)
    return chunks or [text[:_MAX_CHUNK_CHARS]]


class TTSEngine:
    """
    Wraps the OpenAI TTS API to synthesise lesson narration scripts to MP3.

    Usage
    -----
      engine = TTSEngine(api_key="sk-...")
      engine.synthesize_to_file("Hello learners...", Path("lesson_1.mp3"))
    """

    VOICES = ("alloy", "echo", "fable", "onyx", "nova", "shimmer")

    def __init__(
        self,
        api_key: str,
        model: str = "tts-1",
        voice: str = "onyx",
    ) -> None:
        if voice not in self.VOICES:
            raise ValueError(f"voice must be one of {self.VOICES}")
        import openai
        self._client = openai.OpenAI(api_key=api_key, timeout=120.0)
        self._model  = model
        self._voice  = voice

    # -- Public API -------------------------------------------------------------

    def synthesize_to_file(self, text: str, output_path: Path) -> Path:
        """Synthesise text to an MP3 file. Creates parent dirs if needed."""
        audio_bytes = self.synthesize_bytes(text)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(audio_bytes)
        return output_path

    def synthesize_bytes(self, text: str) -> bytes:
        """Synthesise text and return raw MP3 bytes."""
        chunks = _split_text(text)
        if len(chunks) == 1:
            return self._call_api(chunks[0])
        return b"".join(self._call_api(chunk) for chunk in chunks)

    # -- Internal ---------------------------------------------------------------

    def _call_api(self, text: str) -> bytes:
        response = self._client.audio.speech.create(
            model=self._model,
            voice=self._voice,
            input=text,
            response_format="mp3",
        )
        return response.content
