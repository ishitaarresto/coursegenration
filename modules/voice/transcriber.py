"""
modules/voice/transcriber.py

Speech-to-text using Sarvam AI (saarika:v2).

Supports 11 Indian languages + Indian-accented English:
    hi-IN  Hindi       en-IN  English (Indian)
    ta-IN  Tamil       te-IN  Telugu
    bn-IN  Bengali     kn-IN  Kannada
    ml-IN  Malayalam   mr-IN  Marathi
    gu-IN  Gujarati    or-IN  Odia
    pa-IN  Punjabi

Set in .env:
    SARVAM_API_KEY=your-key
    SARVAM_LANGUAGE=hi-IN   (match your learner base)

Accepted audio formats: webm, wav, mp3, ogg, m4a, flac
"""

from __future__ import annotations

import io

_STT_URL = "https://api.sarvam.ai/speech-to-text"

_MIME: dict[str, str] = {
    "webm": "audio/webm",
    "mp3":  "audio/mpeg",
    "wav":  "audio/wav",
    "ogg":  "audio/ogg",
    "m4a":  "audio/mp4",
    "flac": "audio/flac",
}

SUPPORTED_LANGUAGES = {
    "hi-IN", "en-IN", "ta-IN", "te-IN", "bn-IN",
    "kn-IN", "ml-IN", "mr-IN", "gu-IN", "or-IN", "pa-IN",
}


def _mime_type(filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "webm"
    return _MIME.get(ext, "audio/webm")


class Transcriber:
    """Wraps Sarvam AI speech-to-text for learner voice input."""

    def __init__(self, api_key: str, language: str = "hi-IN") -> None:
        if language not in SUPPORTED_LANGUAGES:
            raise ValueError(
                f"Unsupported language '{language}'. "
                f"Supported: {sorted(SUPPORTED_LANGUAGES)}"
            )
        try:
            import requests as _req
            self._requests = _req
        except ImportError as exc:
            raise RuntimeError(
                "Transcriber requires 'requests'.\n"
                "Install with:  pip install requests"
            ) from exc

        self._api_key  = api_key
        self._language = language

    def transcribe(self, audio_bytes: bytes, filename: str = "audio.webm") -> str:
        """
        Transcribe audio bytes to text.

        audio_bytes : raw mic recording from the browser
        filename    : original filename — sets the Content-Type for Sarvam
        Returns transcribed text, or empty string if Sarvam detected silence.
        """
        response = self._requests.post(
            _STT_URL,
            headers={"api-subscription-key": self._api_key},
            files={
                "file": (filename, io.BytesIO(audio_bytes), _mime_type(filename)),
            },
            data={
                "language_code":   self._language,
                "model":           "saarika:v2",
                "with_timestamps": "false",
            },
            timeout=60,
        )
        response.raise_for_status()
        return (response.json().get("transcript") or "").strip()
