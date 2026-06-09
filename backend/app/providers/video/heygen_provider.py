"""HeyGen Video Agent connector — v3 API.

Flow:
    1. submit()   POST  /v3/video-agents          → session_id
    2. poll_session()  GET /v3/video-agents/{id}  → wait for video_id
    3. poll_video()    GET /v3/videos/{video_id}  → wait for video_url
    4. download()  GET  <video_url>               → bytes → .mp4

Engine prompt is built by style_prompts.build_style_brief(). This connector only
transports it. Set HEYGEN_API_KEY in backend/.env to activate.
"""
from __future__ import annotations

import time
from pathlib import Path

import httpx

from app.core.config import settings


class HeyGenNotConfigured(RuntimeError):
    pass


class HeyGenError(RuntimeError):
    pass


def is_configured() -> bool:
    return bool(settings.heygen_api_key.strip())


def remaining_credits() -> int | None:
    """Return current HeyGen API credit balance (free, read-only). None if unknown."""
    if not is_configured():
        return None
    try:
        with _client() as c:
            r = c.get("/v2/user/remaining_quota")
            if r.status_code == 200:
                return int(r.json().get("data", {}).get("remaining_quota", 0))
    except Exception:
        return None
    return None


def preflight(estimated_credits: float = 1.0) -> None:
    """Refuse to submit if credits can't cover the job — prevents wasted/failed renders.

    A failed HeyGen submit can still reserve credits, so we check FIRST. This is the
    core of the credit-economy system: never fire a paid call we can't afford.
    """
    bal = remaining_credits()
    if bal is None:
        return  # can't verify — let submit handle it
    if bal < estimated_credits:
        raise HeyGenError(
            f"Not enough HeyGen credits: {bal} left, ~{estimated_credits:.0f} needed. "
            "Top up at app.heygen.com → Billing, or use the free 'Claude Animated' style."
        )


def _client() -> httpx.Client:
    if not is_configured():
        raise HeyGenNotConfigured(
            "HEYGEN_API_KEY is not set in backend/.env. "
            "Add it there to enable Animated Scene / Whiteboard Doodle / Hybrid styles."
        )
    return httpx.Client(
        base_url=settings.heygen_base_url,
        headers={"X-Api-Key": settings.heygen_api_key, "Content-Type": "application/json"},
        timeout=90.0,
    )


# ── Step 1: submit prompt → session_id ───────────────────────────────────────

def submit(prompt: str, *, title: str) -> str:
    """POST to /v3/video-agents — returns video_id directly (no session poll needed).

    The v3 /video-agents endpoint accepts ONLY a `prompt` field. The "no avatar"
    requirement is enforced entirely inside the prompt text (see style_prompts.py),
    NOT via API params — extra params are rejected with HTTP 400.
    """
    payload = {"prompt": prompt[:4000]}
    with _client() as c:
        r = c.post("/v3/video-agents", json=payload)
        if r.status_code == 402 or "insufficient_credit" in r.text:
            raise HeyGenError(
                "HeyGen credits exhausted. Top up at app.heygen.com → Billing, "
                "then try again. (Tip: use the free 'Claude Animated' style meanwhile.)"
            )
        if r.status_code >= 400:
            raise HeyGenError(f"submit failed [{r.status_code}]: {r.text}")
        data = r.json().get("data", {})
        # v3 returns video_id immediately in the submit response
        video_id = data.get("video_id") or data.get("id")
        if not video_id:
            raise HeyGenError(f"no video_id in submit response: {r.text}")
        return video_id


# ── Step 3: poll video → download URL ────────────────────────────────────────

def poll_video(video_id: str, *, interval: float = 8.0, timeout: float = 2400.0) -> str:
    """Poll until the video is ready. HeyGen can take 5-30 min per video."""
    deadline = time.monotonic() + timeout
    with _client() as c:
        while time.monotonic() < deadline:
            r = c.get(f"/v3/videos/{video_id}")
            if r.status_code >= 400:
                raise HeyGenError(f"video poll failed [{r.status_code}]: {r.text}")
            data = r.json().get("data", {})
            status = data.get("status", "")
            if status == "completed":
                url = data.get("video_url")
                if not url:
                    raise HeyGenError("completed but no video_url in response")
                return url
            if status in {"failed", "error"}:
                # HeyGen uses failure_code + failure_message, not 'error'
                code = data.get("failure_code", "")
                msg = data.get("failure_message", "") or data.get("error", "unknown")
                if "INSUFFICIENT_CREDIT" in code or "PAYMENT" in code:
                    raise HeyGenError(
                        f"HeyGen credit exhausted ({code}). "
                        "Top up at app.heygen.com → Billing before generating more videos."
                    )
                raise HeyGenError(f"HeyGen generation failed [{code}]: {msg}")
            time.sleep(interval)
    raise HeyGenError(
        f"HeyGen timed out after {timeout/60:.0f} min for video {video_id}. "
        "The video may still be rendering — check app.heygen.com and retry."
    )


# ── Step 4: download MP4 ──────────────────────────────────────────────────────

def download(url: str, out_path: Path) -> Path:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with httpx.Client(timeout=300.0) as c, c.stream("GET", url) as r:
        if r.status_code >= 400:
            raise HeyGenError(f"download failed [{r.status_code}]")
        with out_path.open("wb") as f:
            for chunk in r.iter_bytes():
                f.write(chunk)
    return out_path


# ── End-to-end convenience ────────────────────────────────────────────────────

def generate(prompt: str, *, title: str, out_path: Path) -> Path:
    """Submit → poll video → download. Returns the MP4 path."""
    video_id = submit(prompt, title=title)
    url = poll_video(video_id)
    return download(url, out_path)
