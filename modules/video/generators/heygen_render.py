"""
modules/video/generators/heygen_render.py

HeyGen Video Agent connector (v3 API).

Flow
----
  1. POST /v3/video-agents  — prompt → video_id
  2. GET  /v3/videos/{id}   — poll until status == "completed" → video_url
  3. GET  <video_url>       — stream download → MP4

Set HEYGEN_API_KEY in .env to activate.  If not set, calling
generate_heygen_video() raises HeyGenNotConfigured.
"""
from __future__ import annotations

import time
from pathlib import Path

import httpx

from api.config import settings
from modules.video.schemas import LessonContent


class HeyGenNotConfigured(RuntimeError):
    pass


class HeyGenError(RuntimeError):
    pass


def is_configured() -> bool:
    return bool(settings.heygen_api_key.strip())


def remaining_credits() -> int | None:
    """Read current credit balance — returns None if the call fails."""
    if not is_configured():
        return None
    try:
        with _client() as c:
            r = c.get("/v2/user/remaining_quota")
            if r.status_code == 200:
                return int(r.json().get("data", {}).get("remaining_quota", 0))
    except Exception:
        pass
    return None


def _client() -> httpx.Client:
    if not is_configured():
        raise HeyGenNotConfigured(
            "HEYGEN_API_KEY is not set in .env. "
            "Add it to enable Animated Scene / Whiteboard Doodle / Hybrid styles."
        )
    return httpx.Client(
        base_url=settings.heygen_base_url,
        headers={
            "X-Api-Key": settings.heygen_api_key,
            "Content-Type": "application/json",
        },
        timeout=90.0,
    )


def _build_prompt(lesson_title: str, lc: LessonContent, style: str, lang: str, voice_preference: str = "male") -> str:
    """Build a concise prompt for the HeyGen Video Agent."""
    takeaways = lc.key_takeaways or []
    summary   = lc.summary or ""

    _vp = voice_preference.lower()
    is_male = _vp in ("male", "m", "rahul", "gokul")
    lang_note = f" Language: {lang}." if lang != "en" else ""

    style_desc = {
        "animated_scene":    "animated motion-graphics (no human presenter, no avatar)",
        "whiteboard_doodle": "whiteboard doodle animation (no human presenter, no avatar)",
        "hybrid":            "hybrid animation combining motion-graphics and whiteboard sketches (no human presenter, no avatar)",
    }.get(style, "animated infographics (no avatar)")

    bullets = "\n".join(f"- {b}" for b in takeaways[:6]) if takeaways else ""

    lines = [
        f"Create a 90-second workplace safety training video.",
        f"Topic: {lesson_title}",
        f"Visual style: {style_desc}.{lang_note}",
        f"Voice: {'male' if is_male else 'female'}, professional authoritative tone.",
        "",
        "Key points to cover:",
        bullets if bullets else f"- {summary or lesson_title}",
        "",
        "Format: animated title card → animated bullet points with safety icons → summary recap card.",
        "Colour coding: red for dangers/hazards, green for safe actions, orange for cautions.",
    ]
    return "\n".join(lines)


def _submit(prompt: str, *, max_retries: int = 4) -> str:
    """POST to /v3/video-agents → returns session_id.

    The Video Agent API returns a session_id immediately; video_id is null at
    this stage and must be retrieved by polling _poll_session() next.

    Retries with exponential backoff for transient 429/5xx responses.
    Permanent failures (402 credits, 400 bad-request) raise immediately.
    """
    delay = 5.0
    last_error: str = ""
    for attempt in range(max_retries + 1):
        with _client() as c:
            r = c.post("/v3/video-agents", json={"prompt": prompt})

        if r.status_code == 402 or "insufficient_credit" in r.text:
            raise HeyGenError(
                "HeyGen credits exhausted. Top up at app.heygen.com → Billing, "
                "then try again. (Tip: use style=modern for free rendering.)"
            )

        # 400 is a permanent client error (bad payload) — don't retry
        if r.status_code == 400:
            raise HeyGenError(f"HeyGen submit failed [400]: {r.text}")

        # Transient: 429 or 5xx
        if r.status_code == 429 or r.status_code >= 500:
            last_error = f"HeyGen submit failed [{r.status_code}]: {r.text}"
            if attempt < max_retries:
                time.sleep(delay)
                delay = min(delay * 2, 60.0)
                continue
            raise HeyGenError(last_error)

        if r.status_code >= 400:
            raise HeyGenError(f"HeyGen submit failed [{r.status_code}]: {r.text}")

        data = r.json().get("data", {})
        session_id = data.get("session_id")
        if not session_id:
            raise HeyGenError(f"No session_id in HeyGen submit response: {r.text}")
        return session_id

    raise HeyGenError(last_error or "HeyGen submit failed after retries.")


def _poll_session(session_id: str, *, interval: float = 5.0, timeout: float = 300.0) -> str:
    """GET /v3/video-agents/{session_id} until video_id is assigned → returns video_id.

    The Video Agent API assigns a video_id asynchronously after the session is
    created. This step bridges the gap between submit and video polling.
    """
    deadline = time.monotonic() + timeout
    with _client() as c:
        while time.monotonic() < deadline:
            r = c.get(f"/v3/video-agents/{session_id}")
            if r.status_code >= 400:
                raise HeyGenError(
                    f"HeyGen session poll failed [{r.status_code}]: {r.text}"
                )
            data     = r.json().get("data", {})
            status   = data.get("status", "")
            video_id = data.get("video_id")
            if video_id:
                return video_id
            if status in {"failed", "error"}:
                raise HeyGenError(
                    f"HeyGen session failed before assigning a video_id: {r.text}"
                )
            time.sleep(interval)
    raise HeyGenError(
        f"HeyGen session {session_id} did not assign a video_id within "
        f"{timeout / 60:.0f} min."
    )


def _poll_video(video_id: str, *, interval: float = 10.0, timeout: float = 2400.0) -> str:
    """Poll /v3/videos/{id} until completed → returns video_url."""
    deadline = time.monotonic() + timeout
    with _client() as c:
        while time.monotonic() < deadline:
            r = c.get(f"/v3/videos/{video_id}")
            if r.status_code >= 400:
                raise HeyGenError(
                    f"HeyGen video poll failed [{r.status_code}]: {r.text}"
                )
            data   = r.json().get("data", {})
            status = data.get("status", "")
            if status == "completed":
                url = data.get("video_url")
                if not url:
                    raise HeyGenError(
                        "HeyGen marked video as completed but returned no video_url."
                    )
                return url
            if status in {"failed", "error"}:
                code = data.get("failure_code", "")
                msg  = data.get("failure_message", "") or data.get("error", "unknown")
                if "INSUFFICIENT_CREDIT" in code or "PAYMENT" in code:
                    raise HeyGenError(
                        f"HeyGen credits exhausted ({code}). "
                        "Top up at app.heygen.com → Billing."
                    )
                raise HeyGenError(f"HeyGen generation failed [{code}]: {msg}")
            time.sleep(interval)
    raise HeyGenError(
        f"HeyGen timed out after {timeout / 60:.0f} min waiting for video {video_id}."
    )


def _download(url: str, out_path: Path) -> Path:
    """Stream download video_url → out_path."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with httpx.Client(timeout=300.0) as c, c.stream("GET", url) as r:
        if r.status_code >= 400:
            raise HeyGenError(f"HeyGen download failed [{r.status_code}].")
        with out_path.open("wb") as f:
            for chunk in r.iter_bytes():
                f.write(chunk)
    return out_path


def generate_heygen_video(
    lesson_id: str,
    lesson_title: str,
    lc: LessonContent,
    style: str,
    lang: str,
    out_path: Path,
    voice_preference: str = "male",
) -> Path:
    """
    End-to-end HeyGen render: build prompt → submit → poll → download.

    Raises HeyGenNotConfigured if HEYGEN_API_KEY is missing.
    Raises HeyGenError on API or credit failures.
    Returns the path to the downloaded MP4 (may be a cached hit).
    """
    if not is_configured():
        raise HeyGenNotConfigured(
            f"Style '{style}' requires HEYGEN_API_KEY in .env."
        )

    # Reuse a previously rendered file to avoid double-charging credits.
    if out_path.exists() and out_path.stat().st_size > 10_000:
        return out_path

    prompt     = _build_prompt(lesson_title, lc, style, lang, voice_preference)
    session_id = _submit(prompt)
    video_id   = _poll_session(session_id)
    url        = _poll_video(video_id)
    return _download(url, out_path)
