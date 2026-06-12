"""Animated motion-graphics engine — FREE, illustration-driven.

Builds a self-playing animated HTML "scene player" using real colorful vector
illustrations (Iconify), CSS keyframe motion, caption boxes and pill labels —
styled to look like professional explainer videos. Three selectable styles:

  - "modern"     : white bg, big colorful illustration + bottom caption box (video-3 look)
  - "flatcolor"  : solid blue gradient bg, illustration bounces in, title (video-1 look)
  - "whiteboard" : white bg, line illustration draws itself, handwritten text (video-2 look)

Recorded live by Playwright (animated_render.py) and muxed with edge-tts narration.
"""
from __future__ import annotations

import html
import json

from app.modules.course_generation import schemas
from app.modules.course_generation.generators.assets import get_illustration

# Fallback emoji per icon hint, used when no SVG is found.
_EMOJI = {
    "warning": "⚠️", "fire": "🔥", "car": "🚗", "road": "🛣️", "bike": "🚲",
    "bicycle": "🚲", "person": "🚶", "eye": "👁️", "speed": "🚦", "sleep": "😴",
    "phone": "📱", "shield": "🛡️", "hardhat": "👷", "check": "✅", "helmet": "🪖",
    "traffic": "🚦", "alert": "🚨", "book": "📘", "star": "⭐",
}

# Map Claude's icon hints -> clean concrete search terms for good illustrations.
_ICON_QUERY = {
    "warning": "warning", "fire": "fire", "car": "car", "road": "road",
    "bike": "bicycle", "bicycle": "bicycle", "person": "person walking",
    "eye": "eye", "speed": "speedometer", "sleep": "sleeping", "phone": "smartphone",
    "shield": "shield", "hardhat": "helmet safety", "check": "checklist",
    "helmet": "helmet", "traffic": "traffic light", "alert": "siren", "star": "star",
}

# Words to strip when deriving an illustration keyword from a heading/title.
_STOP = {"the", "a", "an", "and", "or", "for", "of", "to", "in", "on", "your",
         "safety", "basics", "common", "understanding", "introduction", "tips",
         "everyone", "practices", "matters", "why", "what", "how", "lesson"}


def _keyword(text: str) -> str:
    """Extract a concrete illustration keyword from a heading/title."""
    words = [w.strip(":.,-").lower() for w in (text or "").split()]
    meaningful = [w for w in words if w and w not in _STOP and len(w) > 2]
    return meaningful[0] if meaningful else (words[0] if words else "safety")


def _query_for(icon: str, heading: str) -> str:
    """Best illustration search term: clean icon hint first, else heading keyword."""
    if icon and icon.lower() in _ICON_QUERY:
        return _ICON_QUERY[icon.lower()]
    return _keyword(heading)


def _e(s: str) -> str:
    return html.escape(s or "")


def _illus(query: str, color: str, fallback_key: str = "") -> str:
    """Return inline SVG illustration, or an emoji span fallback."""
    svg = get_illustration(query, color=color)
    if svg:
        return f'<div class="illus-svg">{svg}</div>'
    emoji = _EMOJI.get(fallback_key.lower(), "📘")
    return f'<div class="illus-emoji">{emoji}</div>'


# ── Scene builders (each returns {dur, html}) ──────────────────
def _scene_title(title: str, subtitle: str, query: str, color: str, dur: float) -> dict:
    return {"dur": dur, "html": f"""
<div class="scene s-title">
  <div class="illus float-in">{_illus(query, color, 'book')}</div>
  <div class="title-text">
    <h1 class="anim-up">{_e(title)}</h1>
    {f'<p class="anim-up d2">{_e(subtitle)}</p>' if subtitle else ''}
  </div>
</div>"""}


def _scene_point(heading: str, bullets: list[str], query: str, color: str,
                 fallback: str, dur: float) -> dict:
    items = "".join(
        f'<li style="animation-delay:{0.5 + i*0.55:.2f}s">{_e(b)}</li>'
        for i, b in enumerate(bullets[:4])
    )
    return {"dur": dur, "html": f"""
<div class="scene s-point">
  <div class="point-left">
    <div class="pill anim-left">{_e(heading)}</div>
    <ul class="point-list">{items}</ul>
  </div>
  <div class="illus pop-in">{_illus(query, color, fallback)}</div>
</div>"""}


def _scene_warning(heading: str, bullets: list[str], color: str, dur: float) -> dict:
    items = "".join(
        f'<li style="animation-delay:{0.5 + i*0.5:.2f}s">⚠ {_e(b)}</li>'
        for i, b in enumerate(bullets[:4])
    )
    return {"dur": dur, "html": f"""
<div class="scene s-warning">
  <div class="warn-pulse"></div>
  <div class="illus shake-in">{_illus('warning sign', '#ffffff', 'warning')}</div>
  <h2 class="anim-up">{_e(heading) or 'Safety Warning'}</h2>
  <ul class="warn-list">{items}</ul>
</div>"""}


def _scene_caption(heading: str, query: str, color: str, fallback: str, dur: float) -> dict:
    """Big centered illustration with a caption box at bottom (video-3 look)."""
    return {"dur": dur, "html": f"""
<div class="scene s-caption">
  <div class="illus big float-in">{_illus(query, color, fallback)}</div>
  <div class="caption-box anim-up d2">{_e(heading)}</div>
</div>"""}


def _scene_summary(heading: str, bullets: list[str], color: str, dur: float) -> dict:
    items = "".join(
        f'<li style="animation-delay:{0.4 + i*0.5:.2f}s">✓ {_e(b)}</li>'
        for i, b in enumerate(bullets[:5])
    )
    return {"dur": dur, "html": f"""
<div class="scene s-summary">
  <div class="illus pop-in">{_illus('checklist complete', '#ffffff', 'check')}</div>
  <h2 class="anim-up">{_e(heading) or 'Key Takeaways'}</h2>
  <ul class="sum-list">{items}</ul>
</div>"""}


def build_scenes(lesson_title: str, lc: schemas.LessonContent,
                 slides: list[schemas.SlideSpec], color: str = "#2563eb") -> list[dict]:
    """Turn a lesson into a timed sequence of illustrated animated scenes."""
    scenes: list[dict] = []
    topic = _keyword(lesson_title)  # clean concrete keyword, e.g. "pedestrian"

    # 1. Title
    scenes.append(_scene_title(lesson_title, (lc.summary or "")[:70], topic, color, 4.0))

    # 2. Key points
    if lc.key_takeaways:
        scenes.append(_scene_point("Key Points", lc.key_takeaways, topic, color, "star", 6.0))

    # 3. One caption scene per important slide (content/diagram), capped
    used = 0
    for s in slides:
        if s.type in ("content", "diagram", "timeline") and s.heading and used < 3:
            q = _query_for(s.icon, s.heading)
            scenes.append(_scene_caption(s.heading, q, color, s.icon, 5.0))
            used += 1

    # 4. Warning scene
    for s in slides:
        if s.type == "warning" and s.bullets:
            scenes.append(_scene_warning(s.heading, s.bullets, color, 5.0))
            break

    # 5. Real-world examples
    if lc.real_world_examples:
        scenes.append(_scene_point("Real Examples", lc.real_world_examples, topic, color, "road", 6.0))

    # 6. Summary
    takeaways = lc.key_takeaways[:4] if lc.key_takeaways else [lc.summary or "Stay safe."]
    scenes.append(_scene_summary("Remember", takeaways, color, 5.0))
    return scenes


# ── CSS for all three styles ───────────────────────────────────
_BASE_CSS = """
* { margin:0; padding:0; box-sizing:border-box; font-family:'Segoe UI',system-ui,sans-serif; }
body { width:1280px; height:720px; overflow:hidden; }
#stage { width:1280px; height:720px; position:relative; }
.scene-wrap { position:absolute; inset:0; opacity:0; transition:opacity .5s ease; }
.scene-wrap.show { opacity:1; }
.scene { position:absolute; inset:0; display:flex; align-items:center; justify-content:center;
         padding:70px; gap:50px; }

/* illustrations */
.illus { display:flex; align-items:center; justify-content:center; z-index:2; }
.illus-svg svg { width:340px; height:340px; }
.illus.big .illus-svg svg { width:420px; height:420px; }
.illus-emoji { font-size:200px; line-height:1; }

/* entrance animations */
.anim-up   { opacity:0; animation:up .8s ease forwards; }
.anim-left { opacity:0; animation:lft .8s ease forwards; }
.float-in  { opacity:0; animation:flt 1s cubic-bezier(.2,1,.3,1) forwards; }
.pop-in    { opacity:0; animation:pop .8s cubic-bezier(.2,1.5,.4,1) forwards; }
.shake-in  { animation:shk 1.2s ease-in-out infinite; }
.d2 { animation-delay:.6s; }
@keyframes up  { from{opacity:0;transform:translateY(40px);} to{opacity:1;transform:none;} }
@keyframes lft { from{opacity:0;transform:translateX(-50px);} to{opacity:1;transform:none;} }
@keyframes flt { from{opacity:0;transform:translateY(60px) scale(.9);} to{opacity:1;transform:none;} }
@keyframes pop { from{opacity:0;transform:scale(.4);} to{opacity:1;transform:scale(1);} }
@keyframes shk { 0%,100%{transform:rotate(0);} 25%{transform:rotate(-7deg);} 75%{transform:rotate(7deg);} }
@keyframes slide { from{opacity:0;transform:translateX(-30px);} to{opacity:1;transform:none;} }

h1 { font-size:54px; font-weight:800; line-height:1.1; }
h2 { font-size:40px; font-weight:700; margin-top:10px; }

/* lists */
ul { list-style:none; }
.point-list li, .warn-list li, .sum-list li {
  font-size:26px; margin:12px 0; padding:14px 24px; border-radius:14px;
  opacity:0; animation:slide .6s ease forwards;
}
.point-left { max-width:560px; }
.pill { display:inline-block; font-size:30px; font-weight:800; padding:12px 30px;
        border-radius:40px; margin-bottom:22px; }

/* caption box (video-3 look) */
.s-caption { flex-direction:column; }
.caption-box { font-size:34px; font-weight:800; padding:18px 40px; border-radius:16px;
               box-shadow:0 8px 30px rgba(0,0,0,.12); }

/* warning */
.s-warning { flex-direction:column; text-align:center; }
.warn-pulse { position:absolute; inset:0; background:radial-gradient(circle,rgba(255,0,0,.3),transparent 60%);
              animation:pulse 1.5s ease-in-out infinite; }
@keyframes pulse { 0%,100%{opacity:.25;} 50%{opacity:.6;} }
.s-summary { flex-direction:column; text-align:center; }
.s-title { gap:60px; }
"""

_STYLE_CSS = {
    "modern": """
body, .scene { background:#ffffff; color:#1e293b; }
.s-warning, .s-summary { color:#fff; }
.s-warning { background:linear-gradient(135deg,#b91c1c,#7f1d1d); }
.s-summary { background:linear-gradient(135deg,#059669,#064e3b); }
.pill { background:#fde68a; color:#92400e; }
.point-list li { background:#f1f5f9; }
.caption-box { background:#fde68a; color:#1e293b; }
.warn-list li, .sum-list li { background:rgba(255,255,255,.18); color:#fff; }
h1 { color:#1e293b; }
""",
    "flatcolor": """
body, .scene { background:linear-gradient(135deg,#1d4ed8,#3b82f6 60%,#0ea5e9); color:#fff; }
.s-summary { background:linear-gradient(135deg,#059669,#064e3b); }
.s-warning { background:linear-gradient(135deg,#b91c1c,#7f1d1d); }
.pill { background:rgba(255,255,255,.2); color:#fff; }
.point-list li { background:rgba(255,255,255,.15); }
.caption-box { background:rgba(255,255,255,.95); color:#1e3a8a; }
.warn-list li, .sum-list li { background:rgba(255,255,255,.18); }
h1, h2 { color:#fff; }
""",
    "whiteboard": """
body, .scene { background:#fdfdfd; color:#1e293b; }
.illus-svg svg { filter:grayscale(.2); }
.pill { background:#e0f2fe; color:#0369a1; border:2px dashed #0ea5e9; }
.point-list li { background:#f8fafc; border-left:3px solid #0ea5e9; }
.caption-box { background:#fff; border:2px solid #1e293b; color:#1e293b; }
.s-warning { background:#fff5f5; color:#b91c1c; }
.s-summary { background:#f0fdf4; color:#065f46; }
.warn-list li { background:#fee2e2; color:#b91c1c; }
.sum-list li { background:#dcfce7; color:#065f46; }
h1,h2 { font-family:'Comic Sans MS','Segoe Print',cursive; }
""",
}


def render_animated_html(lesson_title: str, scenes: list[dict], total_audio: float,
                         style: str = "modern") -> str:
    scene_dur_sum = sum(s["dur"] for s in scenes) or 1
    scale = max(total_audio / scene_dur_sum, 0.5) if total_audio else 1.0
    timed = [{"html": s["html"], "dur": s["dur"] * scale} for s in scenes]

    scene_divs = "\n".join(
        f'<div class="scene-wrap" data-dur="{s["dur"]:.2f}">{s["html"]}</div>' for s in timed
    )
    durations = json.dumps([s["dur"] for s in timed])
    style_css = _STYLE_CSS.get(style, _STYLE_CSS["modern"])

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>{_BASE_CSS}{style_css}</style></head>
<body>
<div id="stage">{scene_divs}</div>
<script>
const durs = {durations};
const wraps = document.querySelectorAll('.scene-wrap');
function show(idx) {{
  wraps.forEach(w => w.classList.remove('show'));
  if (idx >= wraps.length) {{ window.__done = true; return; }}
  const w = wraps[idx];
  w.classList.add('show');
  w.querySelectorAll('[class*=anim-], [class*=-in], li').forEach(el => {{
    el.style.animation = 'none'; void el.offsetWidth; el.style.animation = '';
  }});
  setTimeout(() => show(idx + 1), durs[idx] * 1000);
}}
window.__done = false;
window.addEventListener('load', () => setTimeout(() => show(0), 250));
</script>
</body></html>"""
