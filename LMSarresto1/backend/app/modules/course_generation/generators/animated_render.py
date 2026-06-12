"""Record the self-playing animated HTML to a real video, synced with narration.

Pipeline (all FREE):
  1. edge-tts  -> narration MP3 (per lesson)
  2. ffprobe   -> measure audio length
  3. animated.py builds timeline-scaled animated HTML
  4. Playwright records the page playing live -> webm (captures CSS motion)
  5. ffmpeg    -> mux narration + webm, trim to audio -> MP4
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from playwright.sync_api import sync_playwright

from app.modules.course_generation import schemas
from app.modules.course_generation.generators.animated import build_scenes, render_animated_html
from app.modules.course_generation.generators.synced import build_cues, render_synced_html
from app.modules.course_generation.generators.tts_router import synthesise, synthesise_with_timings
from app.modules.course_generation.generators.video import _ffmpeg, _ffprobe


def _audio_len(path: Path) -> float:
    r = subprocess.run(
        [_ffprobe(), "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True, check=True,
    )
    return float(r.stdout.strip() or "20")


def generate_animated_video(
    lesson_id: int,
    lesson_title: str,
    lesson_content: schemas.LessonContent,
    slides: list[schemas.SlideSpec],
    lang: str = "en",
    style: str = "modern",
) -> Path:
    work = Path("media") / "animated" / str(lesson_id)
    work.mkdir(parents=True, exist_ok=True)

    # 1. Narration audio (localise first so audio matches the language)
    from app.modules.course_generation.generators.translate import translate_script
    from app.providers.llm import get_llm

    audio = work / f"{lang}.mp3"
    script = lesson_content.narration_script or lesson_content.summary or lesson_title
    script = translate_script(get_llm(), script, lang)
    synthesise(script, lang, audio)
    dur = _audio_len(audio)

    # 2. Build animated HTML scaled to audio length
    scenes = build_scenes(lesson_title, lesson_content, slides)
    html_doc = render_animated_html(lesson_title, scenes, dur, style=style)
    html_file = work / "scene.html"
    html_file.write_text(html_doc, encoding="utf-8")

    _record_and_mux(html_file, audio, dur, work)
    return work / f"{lang}.mp4"


def _record_and_mux(html_file: Path, audio: Path, dur: float, work: Path) -> Path:
    """Record the playing HTML with Playwright, then mux narration -> MP4."""
    out = work / f"{audio.stem}.mp4"
    video_tmp_dir = work / "_rec"
    video_tmp_dir.mkdir(exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=["--autoplay-policy=no-user-gesture-required"])
        context = browser.new_context(
            viewport={"width": 1280, "height": 720},
            record_video_dir=str(video_tmp_dir),
            record_video_size={"width": 1280, "height": 720},
        )
        page = context.new_page()
        page.goto(html_file.resolve().as_uri())
        page.wait_for_timeout(int((dur + 1.0) * 1000))
        context.close()
        browser.close()

    webms = list(video_tmp_dir.glob("*.webm"))
    if not webms:
        raise RuntimeError("Playwright did not produce a video recording")

    subprocess.run([
        _ffmpeg(), "-y",
        "-i", str(webms[0]),
        "-i", str(audio),
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "160k",
        "-shortest",
        "-vf", "scale=1280:720,fps=30",
        str(out),
    ], check=True, capture_output=True)
    return out


def generate_synced_video(
    lesson_id: int,
    lesson_title: str,
    lesson_content: schemas.LessonContent,
    lang: str = "en",
    style: str = "modern",
) -> Path:
    """Word-synced video: illustrations pop in exactly when their word is spoken."""
    work = Path("media") / "synced" / str(lesson_id)
    work.mkdir(parents=True, exist_ok=True)

    # 1. Narration + per-word timings (localise first so audio matches the language)
    from app.modules.course_generation.generators.translate import translate_script
    from app.providers.llm import get_llm

    audio = work / f"{lang}.mp3"
    script = lesson_content.narration_script or lesson_content.summary or lesson_title
    script = translate_script(get_llm(), script, lang)
    words = synthesise_with_timings(script, lang, audio)
    dur = _audio_len(audio)

    # 2. Build keyword cues + synced HTML
    cues = build_cues(words)
    html_doc = render_synced_html(lesson_title, words, cues, dur, style=style)
    html_file = work / "scene.html"
    html_file.write_text(html_doc, encoding="utf-8")

    # 3. Record + mux
    _record_and_mux(html_file, audio, dur, work)
    return work / f"{lang}.mp4"


def generate_whiteboard_video(
    lesson_id: int,
    lesson_title: str,
    lesson_content: schemas.LessonContent,
    lang: str = "en",
) -> Path:
    """Whiteboard-style teaching video.

    Pipeline:
      1. edge-tts → narration MP3 + per-word timings
      2. Claude → whiteboard scene plan (scenes, elements, delays, colours)
      3. whiteboard.py → animated HTML (slide-in bullets, bouncing questions,
         spring-pop icons, karaoke captions, hand-drawn underlines)
      4. Playwright records HTML → WebM
      5. FFmpeg muxes narration → MP4
    """
    from app.modules.course_generation.generators.translate import translate_script
    from app.modules.course_generation.generators.whiteboard import render_whiteboard_html
    from app.modules.course_generation.generators.whiteboard_plan import (
        generate_whiteboard_plan,
    )
    from app.providers.llm import get_llm

    work = Path("media") / "whiteboard" / str(lesson_id)
    work.mkdir(parents=True, exist_ok=True)

    llm = get_llm()

    # 1. Localise the script FIRST so audio, captions, and bullets all match the
    #    chosen language (edge-tts only speaks the text it's given — it never
    #    translates). For English this is a no-op.
    script = lesson_content.narration_script or lesson_content.summary or lesson_title
    script = translate_script(llm, script, lang)

    # 2. Narration + word timings (now in the target language)
    audio = work / f"{lang}.mp3"
    words = synthesise_with_timings(script, lang, audio)
    dur = _audio_len(audio)

    # 3. LLM scene plan (built from the localised script; icon queries stay English)
    plan = generate_whiteboard_plan(llm, script, lesson_title)

    # 3. Build animated HTML
    html_doc = render_whiteboard_html(lesson_title, plan, words, dur)
    html_file = work / "scene.html"
    html_file.write_text(html_doc, encoding="utf-8")

    # 4 + 5. Record + mux
    _record_and_mux(html_file, audio, dur, work)
    return work / f"{lang}.mp4"
