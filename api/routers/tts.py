"""
api/routers/tts.py

POST  /api/v1/tts/speak          Synthesise text → stores MP3 in memory → returns {audio_id, url}
GET   /api/v1/tts/audio/{id}     Stream the stored MP3 (expires 5 min)

Flow
----
1. Flutter POSTs text → backend calls Sarvam TTS → stores MP3 bytes under a UUID.
2. Backend returns {"audio_id": "...", "url": "/api/v1/tts/audio/UUID"}.
3. Flutter sets AudioElement.src = full URL and calls play() immediately.
   The browser streams the audio natively — no binary data handling in Dart.

Requires SARVAM_API_KEY in .env.
"""

from __future__ import annotations

import asyncio
import time
import uuid

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel

router = APIRouter(prefix="/api/v1/tts", tags=["TTS"])

_TTL_SECS = 300  # 5 minutes
_store: dict[str, tuple[bytes, float]] = {}  # audio_id → (mp3_bytes, created_at)


def _evict() -> None:
    now = time.time()
    for k in [k for k, (_, ts) in list(_store.items()) if now - ts > _TTL_SECS]:
        del _store[k]


def _get_engine(request: Request):
    engine = getattr(request.app.state, "tts_engine", None)
    if engine is None:
        raise HTTPException(
            status_code=503,
            detail="TTS not available — set SARVAM_API_KEY in .env and restart the server.",
        )
    return engine


class SpeakRequest(BaseModel):
    text: str
    voice: str = ""


@router.post("/speak")
async def speak(body: SpeakRequest, request: Request):
    """
    Synthesise text via Sarvam TTS and return a one-time streaming URL.

    The frontend sets AudioElement.src to the returned URL and calls play() —
    the browser streams the MP3 directly without any binary data handling in Dart.
    Audio is held in memory for 5 minutes; re-request if it expires.
    Pass `voice` to override the default Sarvam speaker (e.g. "ritu", "rahul").
    """
    text = body.text.strip()[:5000]
    if not text:
        raise HTTPException(status_code=400, detail="text is required")

    if body.voice:
        from modules.video.generators.sarvam_tts import SarvamTTSEngine, is_configured
        if is_configured():
            engine = SarvamTTSEngine(lang="en-in", speaker=body.voice)
        else:
            engine = _get_engine(request)
    else:
        engine = _get_engine(request)

    mp3_bytes: bytes = await asyncio.to_thread(engine.synthesize_bytes, text)
    _evict()
    audio_id = str(uuid.uuid4())
    _store[audio_id] = (mp3_bytes, time.time())
    return {"audio_id": audio_id, "url": f"/api/v1/tts/audio/{audio_id}"}


@router.get("/audio/{audio_id}")
def get_audio(audio_id: str):
    """Stream a previously synthesised MP3. Expires 5 minutes after generation."""
    entry = _store.get(audio_id)
    if entry is None:
        raise HTTPException(status_code=404, detail="Audio not found or expired.")
    mp3_bytes, created_at = entry
    if time.time() - created_at > _TTL_SECS:
        del _store[audio_id]
        raise HTTPException(status_code=404, detail="Audio expired.")
    return Response(content=mp3_bytes, media_type="audio/mpeg")
