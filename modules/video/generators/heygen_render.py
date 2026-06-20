"""
modules/video/generators/heygen_render.py

HeyGen v2 Avatar Video connector.

Flow
----
  1. POST /v2/video/generate  — avatar + narration text → video_id
  2. GET  /v1/video_status.get?video_id={id}  — poll until completed → video_url
  3. GET  <video_url>  — stream download → MP4

Long narration scripts are automatically split into multiple clips (one
video_inputs segment per paragraph block) to stay within HeyGen's per-clip
character limit.

Set HEYGEN_API_KEY in .env to activate.
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


# ── Avatar / voice catalogue ───────────────────────────────────────────────────

# Indian professional avatars — change these IDs to swap presenters
_AVATARS: dict[str, str] = {
    "male":   "Aditya_public_1",              # Indian male, blue blazer
    "female": "Kavya_standing_indoor_front",  # Indian female, indoor
}

# Voice IDs mapped by (language-prefix, gender)
# To add more languages, append entries like ("ta", "male"): "voice_id"
_VOICES: dict[tuple[str, str], str] = {
    ("en", "male"):   "RXQsBg4dCZCv2gRze9PW",
    ("en", "female"): "s1kSvfYw2QOXqJEFnpRH",
    ("hi", "male"):   "62695468af454e1784d782c846223ae4",
    ("hi", "female"): "6255f703bfd94afe810f06d3186a9353",
}

_DEFAULT_AVATAR = "Aditya_public_1"
_DEFAULT_VOICE  = "RXQsBg4dCZCv2gRze9PW"
_MAX_CHARS      = 1400   # HeyGen per-clip text limit


# ── Helpers ───────────────────────────────────────────────────────────────────

def is_configured() -> bool:
    return bool(settings.heygen_api_key.strip())


def remaining_credits() -> int | None:
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
            "Add it to enable HeyGen avatar video rendering."
        )
    return httpx.Client(
        base_url=settings.heygen_base_url,
        headers={
            "X-Api-Key": settings.heygen_api_key,
            "Content-Type": "application/json",
        },
        timeout=90.0,
    )


def _pick_avatar(voice_preference: str) -> str:
    vp = voice_preference.lower()
    gender = "female" if vp in ("female", "f", "ritu", "kavya") else "male"
    return _AVATARS.get(gender, _DEFAULT_AVATAR)


def _pick_voice(lang: str, voice_preference: str) -> str:
    vp = voice_preference.lower()
    gender = "female" if vp in ("female", "f", "ritu", "kavya") else "male"
    lang_prefix = lang.split("-")[0].lower()  # "en-IN" → "en", "hi-IN" → "hi"
    return _VOICES.get((lang_prefix, gender), _DEFAULT_VOICE)


def _split_text(text: str) -> list[str]:
    """Split narration into ≤_MAX_CHARS segments at paragraph boundaries."""
    text = text.strip()
    if len(text) <= _MAX_CHARS:
        return [text]

    segments: list[str] = []
    current = ""

    for para in text.split("\n\n"):
        para = para.strip()
        if not para:
            continue
        if len(current) + len(para) + 2 <= _MAX_CHARS:
            current = (current + "\n\n" + para).strip() if current else para
        else:
            if current:
                segments.append(current)
            # Paragraph itself too long — split by sentence
            if len(para) > _MAX_CHARS:
                for sentence in para.replace(". ", ".||").split("||"):
                    s = sentence.strip()
                    if not s:
                        continue
                    if len(current) + len(s) + 1 <= _MAX_CHARS:
                        current = (current + " " + s).strip() if current else s
                    else:
                        if current:
                            segments.append(current)
                        current = s[:_MAX_CHARS]
            else:
                current = para

    if current:
        segments.append(current)

    return segments or [text[:_MAX_CHARS]]


def _build_narration(lesson_title: str, lc: LessonContent) -> str:
    """Return the best available narration text for this lesson."""
    if lc.narration_script and lc.narration_script.strip():
        return lc.narration_script.strip()
    # Fallback: build from key takeaways + summary
    parts: list[str] = [f"{lesson_title}."]
    if lc.key_takeaways:
        parts.append("Key points: " + ". ".join(lc.key_takeaways[:6]) + ".")
    if lc.summary:
        parts.append(lc.summary)
    return " ".join(parts)


# ── API calls ─────────────────────────────────────────────────────────────────

def _submit(avatar_id: str, voice_id: str, text_segments: list[str]) -> str:
    """POST /v2/video/generate → video_id."""
    video_inputs = [
        {
            "character": {
                "type": "avatar",
                "avatar_id": avatar_id,
                "avatar_style": "normal",
            },
            "voice": {
                "type": "text",
                "input_text": seg,
                "voice_id": voice_id,
                "speed": 1.0,
            },
        }
        for seg in text_segments
    ]

    delay = 5.0
    last_err = ""
    for attempt in range(4):
        with _client() as c:
            r = c.post("/v2/video/generate", json={
                "video_inputs": video_inputs,
                "dimension": {"width": 1280, "height": 720},
            })

        if r.status_code == 402 or "insufficient_credit" in r.text:
            raise HeyGenError(
                "HeyGen credits exhausted. Top up at app.heygen.com → Billing."
            )
        if r.status_code == 400:
            raise HeyGenError(f"HeyGen submit failed [400]: {r.text}")
        if r.status_code == 429 or r.status_code >= 500:
            last_err = f"HeyGen submit [{r.status_code}]: {r.text}"
            if attempt < 3:
                time.sleep(delay)
                delay = min(delay * 2, 60.0)
                continue
            raise HeyGenError(last_err)
        if r.status_code >= 400:
            raise HeyGenError(f"HeyGen submit failed [{r.status_code}]: {r.text}")

        video_id = r.json().get("data", {}).get("video_id")
        if not video_id:
            raise HeyGenError(f"No video_id in HeyGen response: {r.text}")
        return video_id

    raise HeyGenError(last_err or "HeyGen submit failed after retries.")


def _poll(video_id: str, *, interval: float = 10.0, timeout: float = 1800.0) -> str:
    """GET /v1/video_status.get until completed → video_url."""
    deadline = time.monotonic() + timeout
    with _client() as c:
        while time.monotonic() < deadline:
            r = c.get(f"/v1/video_status.get?video_id={video_id}")
            if r.status_code >= 400:
                raise HeyGenError(f"HeyGen poll failed [{r.status_code}]: {r.text}")

            data   = r.json().get("data", {})
            status = data.get("status", "")

            if status == "completed":
                url = data.get("video_url")
                if not url:
                    raise HeyGenError("HeyGen completed but returned no video_url.")
                return url

            if status in {"failed", "error"}:
                msg = data.get("error") or "unknown"
                raise HeyGenError(f"HeyGen generation failed: {msg}")

            time.sleep(interval)

    raise HeyGenError(
        f"HeyGen timed out after {timeout / 60:.0f} min for video {video_id}."
    )


def _download(url: str, out_path: Path) -> Path:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with httpx.Client(timeout=300.0) as c, c.stream("GET", url) as r:
        if r.status_code >= 400:
            raise HeyGenError(f"HeyGen download failed [{r.status_code}].")
        with out_path.open("wb") as f:
            for chunk in r.iter_bytes():
                f.write(chunk)
    return out_path


# ── Public API ────────────────────────────────────────────────────────────────

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
    End-to-end HeyGen v2 avatar render:
      build narration → split → submit → poll → download.

    Raises HeyGenNotConfigured if HEYGEN_API_KEY is missing.
    Raises HeyGenError on API or credit failures.
    Returns path to the downloaded MP4.
    """
    if not is_configured():
        raise HeyGenNotConfigured(
            f"Style '{style}' requires HEYGEN_API_KEY in .env."
        )

    # Return cached file if already rendered
    if out_path.exists() and out_path.stat().st_size > 10_000:
        return out_path

    narration      = _build_narration(lesson_title, lc)
    segments       = _split_text(narration)
    avatar_id      = _pick_avatar(voice_preference)
    voice_id       = _pick_voice(lang, voice_preference)

    # Pre-flight credit check — 10 credits/min; Hindi ~100 wpm, English ~130 wpm
    word_count   = len(narration.split())
    wpm          = 100 if lang.startswith("hi") else 130
    est_minutes  = word_count / wpm
    est_credits  = int(est_minutes * 10) + 5   # +5 safety margin
    bal          = remaining_credits()
    if bal is not None and bal < est_credits:
        raise HeyGenError(
            f"Insufficient HeyGen credits: {bal} remaining, "
            f"~{est_credits} needed for {word_count}-word scene (~{est_minutes:.1f} min). "
            "Top up at app.heygen.com → Billing."
        )

    video_id = _submit(avatar_id, voice_id, segments)
    url      = _poll(video_id)
    return _download(url, out_path)
