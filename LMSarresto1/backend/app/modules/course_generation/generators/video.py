"""Video generation pipeline — 100% FREE tools."""
from __future__ import annotations

import glob
import os
import re
import shutil
import subprocess
from pathlib import Path

from playwright.sync_api import sync_playwright


# ── Locate ffmpeg/ffprobe regardless of PATH ──────────────────
def _find_bin(name: str) -> str:
    """Find ffmpeg/ffprobe: checks PATH first, then known WinGet/Chocolatey/Scoop locations."""
    found = shutil.which(name)
    if found:
        return found
    # WinGet installs to a long versioned path — glob for it
    patterns = [
        rf"C:\Users\*\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg*\ffmpeg-*\bin\{name}.exe",
        rf"C:\ProgramData\chocolatey\bin\{name}.exe",
        rf"C:\tools\ffmpeg\bin\{name}.exe",
        rf"C:\ffmpeg\bin\{name}.exe",
        rf"C:\Program Files\ffmpeg\bin\{name}.exe",
    ]
    for pattern in patterns:
        matches = glob.glob(pattern, recursive=False)
        if matches:
            return matches[0]
    raise FileNotFoundError(
        f"{name} not found. Make sure ffmpeg is installed and in your PATH. "
        "Download from https://ffmpeg.org/download.html"
    )


_FFMPEG  = None
_FFPROBE = None

def _ffmpeg() -> str:
    global _FFMPEG
    if _FFMPEG is None:
        _FFMPEG = _find_bin("ffmpeg")
    return _FFMPEG

def _ffprobe() -> str:
    global _FFPROBE
    if _FFPROBE is None:
        _FFPROBE = _find_bin("ffprobe")
    return _FFPROBE

from app.modules.course_generation.generators.tts import synthesise


def _slide_count_from_html(slides_html: str) -> int:
    return max(slides_html.count("<section"), 1)


def screenshot_slides(
    slides_url: str, lesson_id: int, slide_count: int
) -> list[Path]:
    """Open the reveal.js deck in headless Chromium and screenshot each slide."""
    out_dir = Path("media") / "frames" / str(lesson_id)
    out_dir.mkdir(parents=True, exist_ok=True)

    paths: list[Path] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.goto(slides_url, wait_until="networkidle", timeout=30000)
        # Give reveal.js time to initialise
        page.wait_for_timeout(1500)

        for i in range(slide_count):
            if i > 0:
                page.keyboard.press("ArrowRight")
                page.wait_for_timeout(700)
            path = out_dir / f"slide_{i:03d}.png"
            page.screenshot(path=str(path), full_page=False)
            paths.append(path)

        browser.close()
    return paths


def _split_narration(script: str, n_slides: int) -> list[str]:
    """Split narration script into roughly equal chunks per slide."""
    sentences = re.split(r"(?<=[.!?])\s+", script.strip())
    if not sentences:
        return [""] * n_slides
    # Distribute sentences across slides
    chunks: list[str] = []
    per = max(1, len(sentences) // n_slides)
    for i in range(n_slides):
        start = i * per
        end = start + per if i < n_slides - 1 else len(sentences)
        chunks.append(" ".join(sentences[start:end]))
    return chunks


def generate_lesson_video(
    lesson_id: int,
    slides_url: str,
    narration_script: str,
    slide_count: int,
    lang: str = "en",
) -> Path:
    """Generate a teaching video for one lesson. Returns path to MP4."""
    video_dir = Path("media") / "videos" / str(lesson_id)
    video_dir.mkdir(parents=True, exist_ok=True)
    out_path = video_dir / f"{lang}.mp4"

    # 1. Screenshot slides
    frames = screenshot_slides(slides_url, lesson_id, slide_count)
    if not frames:
        raise RuntimeError("No slide frames captured")

    # 2. Split narration and generate per-slide audio
    chunks = _split_narration(narration_script, len(frames))
    audio_dir = Path("media") / "audio" / str(lesson_id) / lang
    audio_dir.mkdir(parents=True, exist_ok=True)

    segment_files: list[Path] = []
    for i, (frame, text) in enumerate(zip(frames, chunks)):
        mp3 = audio_dir / f"seg_{i:03d}.mp3"
        if text.strip():
            synthesise(text, lang, mp3)
        else:
            # Silence: create 2s silent mp3 via ffmpeg
            _create_silence(mp3, 2.0)
        segment_files.append(mp3)

    # 3. Build video: each frame shown for the duration of its audio clip
    _assemble_video(frames, segment_files, out_path)
    return out_path


def _create_silence(path: Path, duration: float) -> None:
    """Create a silent MP3 of given duration using ffmpeg."""
    subprocess.run(
        [_ffmpeg(), "-y", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono",
         "-t", str(duration), "-q:a", "9", "-acodec", "libmp3lame", str(path)],
        check=True, capture_output=True,
    )


def _get_audio_duration(path: Path) -> float:
    """Return MP3 duration in seconds using ffprobe."""
    result = subprocess.run(
        [_ffprobe(), "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True, check=True,
    )
    return float(result.stdout.strip() or "2")


def _assemble_video(
    frames: list[Path], audio_segments: list[Path], out_path: Path
) -> None:
    """Combine frame images + audio segments into a single MP4 via ffmpeg."""
    tmp_dir = out_path.parent / "_tmp"
    tmp_dir.mkdir(exist_ok=True)

    clips: list[Path] = []
    for i, (frame, audio) in enumerate(zip(frames, audio_segments)):
        duration = _get_audio_duration(audio)
        clip = tmp_dir / f"clip_{i:03d}.mp4"
        subprocess.run([
            _ffmpeg(), "-y",
            "-loop", "1", "-i", str(frame),
            "-i", str(audio),
            "-c:v", "libx264", "-tune", "stillimage",
            "-c:a", "aac", "-b:a", "128k",
            "-pix_fmt", "yuv420p",
            "-t", str(duration + 0.3),
            "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2",
            str(clip),
        ], check=True, capture_output=True)
        clips.append(clip)

    # Write concat list
    list_file = tmp_dir / "concat.txt"
    list_file.write_text("\n".join(f"file '{c.resolve()}'" for c in clips))

    # Concatenate all clips
    subprocess.run([
        _ffmpeg(), "-y", "-f", "concat", "-safe", "0",
        "-i", str(list_file),
        "-c", "copy", str(out_path),
    ], check=True, capture_output=True)

    shutil.rmtree(tmp_dir, ignore_errors=True)
