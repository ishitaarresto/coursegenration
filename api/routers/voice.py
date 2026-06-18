"""
api/routers/voice.py

POST  /api/v1/voice/session/{session_id}   Full voice round-trip: audio in → audio out
POST  /api/v1/voice/transcribe             Transcribe audio to text only (no tutor)
GET   /api/v1/voice/audio/{audio_id}       Stream synthesized voice reply (expires 5 min)

Voice round-trip flow
---------------------
1. Frontend records mic → sends webm/mp3/wav as multipart upload
2. Whisper API transcribes it to text
3. Text is sent to the tutor chat engine (same session, same history)
4. Tutor's reply is synthesized to speech via OpenAI TTS
5. Returns JSON: transcription + text reply + audio_id
6. Frontend fetches GET /audio/{audio_id} and plays it

Both OPENAI_API_KEY (Whisper + TTS) and ANTHROPIC_API_KEY (tutor) are required.
If TTS is unavailable, the endpoint still returns transcription + text reply
with audio_id: null — the frontend can fall back to displaying the text.
"""

from __future__ import annotations

import asyncio
import logging
import time
import uuid

import re as _re

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import Response

logger = logging.getLogger("arresto.voice")

from api.dependencies import (
    get_embedder,
    get_progress_tracker,
    get_retrieval_pipeline,
    get_vector_store,
)
from api.schemas import ChatRequest, VoiceChatResponse
from api.routers.chat import _process_chat

# Shared session store and engine factory from the tutor router
from api.routers.tutor import _session_store, _get_engine


def _strip_markdown(text: str) -> str:
    """Remove markdown syntax before sending text to Sarvam TTS."""
    return (
        _re.sub(r'\*{1,3}', '', text)
        .replace('`', '')
        .replace('~', '')
        .replace('>', '')
        .replace('#', '')
        .replace('•', '')
        .replace('✨', '')
        .replace('📍', '')
        .replace('📝', '')
        .replace('①②③④⑤', '')
        .strip()
    )

router = APIRouter(prefix="/api/v1/voice", tags=["Voice Assistant"])

# In-memory store for synthesized reply audio — keyed by a one-time audio_id.
# Entries expire after 5 minutes and are evicted lazily on access.
_AUDIO_TTL_SECS = 300
_voice_audio: dict[str, tuple[bytes, float]] = {}  # audio_id → (mp3_bytes, created_at)


# -- Helpers --------------------------------------------------------------------

def _require_transcriber(request: Request):
    t = getattr(request.app.state, "transcriber", None)
    if t is None:
        raise HTTPException(
            status_code=503,
            detail=(
                "Speech-to-text is not available. "
                "Set SARVAM_API_KEY in your .env file and restart the server."
            ),
        )
    return t


def _get_tts(request: Request):
    return getattr(request.app.state, "tts_engine", None)


def _evict_expired() -> None:
    now = time.time()
    stale = [k for k, (_, ts) in _voice_audio.items() if now - ts > _AUDIO_TTL_SECS]
    for k in stale:
        del _voice_audio[k]


# -- Routes ---------------------------------------------------------------------

@router.post("/chat")
async def voice_rag_chat(
    request:            Request,
    audio:              UploadFile = File(..., description="Mic recording — webm, mp3, wav, ogg, or m4a"),
    lesson_id:          str | None = Form(None),
    course_id:          str | None = Form(None),
    timestamp_secs:     str | None = Form(None),   # sent as string from multipart
    history:            str | None = Form(None),   # JSON-encoded list of {role, text}
    vector_store=       Depends(get_vector_store),
    embedder=           Depends(get_embedder),
    retrieval_pipeline= Depends(get_retrieval_pipeline),
):
    """
    Full voice round-trip with the RAG knowledge base (Arresto AI companion).

    Audio → Sarvam STT → RAG retrieval + Claude answer → Sarvam TTS

    Returns:
      transcription — what Sarvam heard (shown as the user's message in chat)
      answer        — Claude's answer from the knowledge base
      audio_id      — fetch the spoken answer from GET /api/v1/voice/audio/{id}
      audio_url     — convenience path: /api/v1/voice/audio/{audio_id} (null if TTS unavailable)
    """
    import json as _json

    # 1. Transcribe audio via Sarvam STT
    transcriber = _require_transcriber(request)
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Audio file is empty.")

    try:
        transcription = await asyncio.to_thread(
            transcriber.transcribe, audio_bytes, audio.filename or "audio.webm"
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {exc}")

    if not transcription:
        raise HTTPException(
            status_code=400,
            detail="Could not transcribe audio — please speak clearly and try again.",
        )

    # 2. RAG chat via the same engine as the text /chat endpoint
    hist: list[dict] = []
    if history:
        try:
            hist = _json.loads(history)
        except Exception:
            hist = []

    ts = None
    if timestamp_secs:
        try:
            ts = int(timestamp_secs)
        except ValueError:
            pass

    chat_req = ChatRequest(
        question=transcription,
        lesson_id=lesson_id,
        course_id=course_id,
        timestamp_secs=ts,
        history=hist,
    )

    try:
        chat_resp = await _process_chat(
            chat_req,
            retrieval_pipeline=retrieval_pipeline,
            embedder=embedder,
            vector_store=vector_store,
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Answer generation failed: {exc}")

    # 3. Synthesize answer via Sarvam TTS (non-fatal — returns text if TTS unavailable)
    audio_id = None
    audio_url = None
    tts = _get_tts(request)
    if tts:
        try:
            clean = _strip_markdown(chat_resp.answer)
            mp3_bytes = await asyncio.to_thread(tts.synthesize_bytes, clean[:4000])
            _evict_expired()
            audio_id = str(uuid.uuid4())
            _voice_audio[audio_id] = (mp3_bytes, time.time())
            audio_url = f"/api/v1/voice/audio/{audio_id}"
        except Exception as exc:
            logger.warning("TTS synthesis failed in voice/chat: %s", exc)

    return {
        "transcription": transcription,
        "answer":        chat_resp.answer,
        "audio_id":      audio_id,
        "audio_url":     audio_url,
    }


@router.post("/session/{session_id}", response_model=VoiceChatResponse)
async def voice_chat(
    session_id:         str,
    request:            Request,
    audio:              UploadFile = File(..., description="Mic recording — webm, mp3, wav, ogg, or m4a"),
    vector_store=       Depends(get_vector_store),
    embedder=           Depends(get_embedder),
    retrieval_pipeline= Depends(get_retrieval_pipeline),
    progress_tracker=   Depends(get_progress_tracker),
):
    """
    Full voice round-trip with the AI Tutor.

    Send a mic recording, get back the tutor's spoken reply.

    **Steps handled server-side:**
    1. Audio → text via OpenAI Whisper
    2. Text → tutor reply via the existing chat engine (adds to session history)
    3. Reply → MP3 via OpenAI TTS

    **Response fields:**
    - `transcription` — what Whisper heard (show this in the chat UI)
    - `reply` — tutor's text answer (show alongside the audio)
    - `audio_id` — fetch the MP3 from `GET /api/v1/voice/audio/{audio_id}`
      (null if TTS is unavailable — fall back to displaying text only)

    Audio expires 5 minutes after generation.
    """
    session = _session_store.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found.")

    # Step 1 — read audio
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Audio file is empty.")

    # Step 2 — transcribe
    transcriber = _require_transcriber(request)
    try:
        transcription = await asyncio.to_thread(
            transcriber.transcribe,
            audio_bytes,
            audio.filename or "audio.webm",
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {exc}")

    if not transcription:
        raise HTTPException(
            status_code=400,
            detail="Could not transcribe audio — please speak clearly and try again.",
        )

    # Step 3 — tutor chat (uses the full retrieval pipeline, session history, weak topics)
    engine = _get_engine(vector_store, embedder, retrieval_pipeline, progress_tracker)
    try:
        reply = await asyncio.to_thread(engine.chat, session, transcription, _session_store)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Tutor response failed: {exc}")

    # Step 4 — synthesize TTS reply (non-fatal: return text if TTS is unavailable)
    audio_id = None
    tts = _get_tts(request)
    if tts:
        try:
            reply_audio = await asyncio.to_thread(tts.synthesize_bytes, reply)
            _evict_expired()
            audio_id = str(uuid.uuid4())
            _voice_audio[audio_id] = (reply_audio, time.time())
        except Exception as exc:
            logger.warning("TTS synthesis failed: %s", exc)

    return VoiceChatResponse(
        session_id=session_id,
        transcription=transcription,
        reply=reply,
        audio_id=audio_id,
        history_length=len(session.history),
    )


@router.post("/transcribe")
async def transcribe_only(
    request: Request,
    audio:   UploadFile = File(..., description="Audio file to transcribe"),
):
    """
    Transcribe audio to text without sending it to the tutor.

    Useful for testing microphone quality or building custom voice flows
    where you want to inspect or edit the transcription before sending.

    Returns: `{ "text": "..." }`
    """
    transcriber = _require_transcriber(request)
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Audio file is empty.")

    try:
        text = await asyncio.to_thread(
            transcriber.transcribe,
            audio_bytes,
            audio.filename or "audio.webm",
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {exc}")

    return {"text": text}


@router.get("/audio/{audio_id}")
def get_voice_audio(audio_id: str):
    """
    Stream a synthesized voice reply MP3.

    Audio is stored in memory and expires 5 minutes after it was generated.
    Re-send your voice message to get a new audio_id if this returns 404.
    """
    entry = _voice_audio.get(audio_id)
    if not entry:
        raise HTTPException(
            status_code=404,
            detail="Audio not found or expired. Re-send your voice message.",
        )

    mp3_bytes, created_at = entry
    if time.time() - created_at > _AUDIO_TTL_SECS:
        del _voice_audio[audio_id]
        raise HTTPException(
            status_code=404,
            detail="Audio expired. Re-send your voice message.",
        )

    return Response(content=mp3_bytes, media_type="audio/mpeg")
