"""ffmpeg/ffprobe helpers and the slide-screenshot video pipeline.

Adapted from LMSarresto — only the ffmpeg utilities are used directly by the
rest of the pipeline; generate_lesson_video() is a fallback screenshot path
kept for reference but not called by the animated renderer.
"""
from __future__ import annotations

import glob
import os
import re
import shutil
import subprocess
from pathlib import Path

from playwright.sync_api import sync_playwright


# ── Locate ffmpeg/ffprobe regardless of PATH ─────────────────────────────────

def _find_bin(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
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
        f"{name} not found. Install ffmpeg and add it to PATH. "
        "Download: https://ffmpeg.org/download.html"
    )


_FFMPEG:  str | None = None
_FFPROBE: str | None = None


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


# ── Screenshot-based pipeline (fallback, not used by animated renderer) ───────

def _slide_count_from_html(slides_html: str) -> int:
    return max(slides_html.count("<section"), 1)


def screenshot_slides(slides_url: str, lesson_id: str, slide_count: int) -> list[Path]:
    """Open a reveal.js deck in headless Chromium and screenshot each slide."""
    out_dir = Path("media") / "frames" / str(lesson_id)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.goto(slides_url, wait_until="networkidle", timeout=30000)
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
    sentences = re.split(r"(?<=[.!?।])\s+", script.strip())
    if not sentences:
        return [""] * n_slides
    chunks: list[str] = []
    per = max(1, len(sentences) // n_slides)
    for i in range(n_slides):
        start = i * per
        end = start + per if i < n_slides - 1 else len(sentences)
        chunks.append(" ".join(sentences[start:end]))
    return chunks


def _create_silence(path: Path, duration: float) -> None:
    subprocess.run(
        [_ffmpeg(), "-y", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono",
         "-t", str(duration), "-q:a", "9", "-acodec", "libmp3lame", str(path)],
        check=True, capture_output=True,
    )


def _get_audio_duration(path: Path) -> float:
    result = subprocess.run(
        [_ffprobe(), "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True, check=True,
    )
    return float(result.stdout.strip() or "2")


def _assemble_video(frames: list[Path], audio_segments: list[Path], out_path: Path) -> None:
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

    list_file = tmp_dir / "concat.txt"
    list_file.write_text("\n".join(f"file '{c.resolve()}'" for c in clips))
    subprocess.run([
        _ffmpeg(), "-y", "-f", "concat", "-safe", "0",
        "-i", str(list_file), "-c", "copy", str(out_path),
    ], check=True, capture_output=True)
    shutil.rmtree(tmp_dir, ignore_errors=True)
