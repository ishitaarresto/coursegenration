"""Animated whiteboard-style video HTML generator.

Visual style:
  - Clean white WHITEBOARD background (like a real classroom whiteboard)
  - A hand holding a marker bobs in the corner — it's always present, teaching
  - Content "draws itself" onto the board scene by scene
  - Rich animated elements appear on the board:
      • SCENARIO split-panels: ❌ wrong vs ✅ correct action
      • WARNING_FLASH: red danger card with pulse animation
      • CHECKLIST: numbered steps that tick in one by one
      • KEY_TERM: definition card in a coloured box
      • STAT: big bold number badge
      • ICON: large illustrated object popping onto the board
      • BULLET: slide-in key points
  - Karaoke captions at the bottom (dark bar)
  - Hand ✍️ bobs / wiggles whenever content is drawing in
"""
from __future__ import annotations

import html
import json

from app.modules.course_generation.generators.assets import get_illustration
from app.modules.course_generation.generators.whiteboard_plan import (
    WBElement,
    WBScene,
    WhiteboardPlan,
)

# ── Helpers ────────────────────────────────────────────────────────────────


def _e(s: str) -> str:
    return html.escape(s or "")


def _caption_groups(words: list[dict], size: int = 10) -> list[dict]:
    groups = []
    for i in range(0, len(words), size):
        chunk = words[i : i + size]
        groups.append(
            {"start": chunk[0]["start"], "end": chunk[-1]["end"], "words": chunk}
        )
    return groups


def _compute_scene_timings(
    scenes: list[WBScene], dur: float
) -> list[tuple[float, float]]:
    total = sum(len(s.script_segment) for s in scenes) or 1
    times: list[tuple[float, float]] = []
    cursor = 0.0
    for s in scenes:
        scene_dur = (len(s.script_segment) / total) * dur
        times.append((cursor, cursor + scene_dur))
        cursor += scene_dur
    return times


def _darken(hex_color: str, factor: float = 0.75) -> str:
    """Darken a hex colour for text use on white background."""
    h = hex_color.lstrip("#")
    if len(h) != 6:
        return "#1e293b"
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"#{int(r*factor):02x}{int(g*factor):02x}{int(b*factor):02x}"


def _tint(hex_color: str, alpha: float = 0.12) -> str:
    """Return a CSS rgba tint of a hex colour (for backgrounds on white)."""
    h = hex_color.lstrip("#")
    if len(h) != 6:
        return f"rgba(59,130,246,{alpha})"
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"rgba({r},{g},{b},{alpha})"


# ── CSS ────────────────────────────────────────────────────────────────────

_CSS = r"""
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans:wght@400;600;700;900&family=Noto+Sans+Devanagari:wght@400;600;700;900&display=swap');
* { margin:0; padding:0; box-sizing:border-box; }
body { width:1280px; height:720px; overflow:hidden;
       font-family:'Noto Sans Devanagari','Noto Sans','Segoe UI',system-ui,Arial,sans-serif; }

/* ── WHITEBOARD BACKGROUND ── */
#stage {
  position:relative; width:1280px; height:720px;
  /* Clean whiteboard — very light off-white with faint horizontal lines */
  background:
    repeating-linear-gradient(
      transparent, transparent 59px,
      rgba(180,200,220,.18) 59px, rgba(180,200,220,.18) 60px
    ),
    linear-gradient(160deg, #fafcff 0%, #f5f8fb 60%, #eef2f7 100%);
}

/* Whiteboard frame border — thin grey line on left and bottom */
#stage::before {
  content:''; position:absolute; inset:0;
  border-left:6px solid #c8d6e0;
  border-bottom:8px solid #b0c4d0;
  pointer-events:none; z-index:5;
}

/* Marker tray at the bottom of the board (above captions) */
#tray {
  position:absolute; left:0; right:0; bottom:96px; height:10px;
  background:linear-gradient(180deg,#b8ccd8,#9bb0be);
  z-index:8;
}

/* ── HEADER ── */
.wb-hdr {
  position:absolute; top:0; left:0; right:0; height:62px;
  display:flex; align-items:center; padding:0 52px;
  background:rgba(255,255,255,.82); backdrop-filter:blur(4px);
  border-bottom:3px solid; /* color set inline per scene */
  z-index:10;
}
.wb-hdr h1 {
  font-size:22px; font-weight:900; flex:1;
  white-space:nowrap; overflow:hidden; text-overflow:ellipsis;
  letter-spacing:.01em; color:#1e293b;
}
.wb-hdr .snum {
  font-size:12px; font-weight:700; letter-spacing:.08em;
  text-transform:uppercase; color:#64748b;
}

/* ── HAND / MARKER indicator ── */
.hand-marker {
  position:absolute; right:22px; top:68px;
  font-size:44px; z-index:25; line-height:1;
  transform-origin:bottom right;
  animation:handIdle 2.2s ease-in-out infinite;
}
.hand-marker.writing {
  animation:handWrite .28s ease-in-out infinite alternate;
}
@keyframes handIdle  {
  0%,100%{transform:rotate(-8deg) translateY(0);}
  50%{transform:rotate(6deg) translateY(-6px);}
}
@keyframes handWrite {
  from{transform:rotate(-12deg) translateX(-3px);}
  to  {transform:rotate( 4deg) translateX( 3px);}
}

/* ── SCENES ── */
.scene {
  position:absolute; top:65px; left:0; right:0; bottom:106px;
  padding:14px 54px 10px;
  display:flex; flex-direction:column; gap:11px;
  opacity:0; pointer-events:none;
}
.scene.active   { opacity:1; pointer-events:auto; }
.scene.entering { animation:sceneIn .5s ease forwards; }
.scene.leaving  { animation:sceneOut .36s ease forwards; pointer-events:none; }
@keyframes sceneIn  { from{opacity:0;transform:translateX(45px);}
                       to{opacity:1;transform:translateX(0);} }
@keyframes sceneOut { from{opacity:1;transform:translateX(0);}
                       to{opacity:0;transform:translateX(-35px);} }

/* Scene title — written on the board */
.sc-title {
  font-size:34px; font-weight:900; line-height:1.2;
  text-transform:uppercase; letter-spacing:.04em;
  opacity:0; transform:translateX(-30px);
  /* Looks like bold marker text */
  text-shadow:2px 2px 0 rgba(0,0,0,.06);
}
.sc-title.show { animation:titleIn .45s ease forwards; }
@keyframes titleIn { to{opacity:1;transform:translateX(0);} }

/* Hand-drawn underline (SVG path that draws itself) */
.uline { overflow:visible; display:block; margin-top:1px; margin-bottom:6px; }
.uline-path {
  fill:none; stroke-linecap:round; stroke-linejoin:round; stroke-width:5;
  stroke-dasharray:700; stroke-dashoffset:700;
}
.uline-path.show { animation:drawLine .6s ease forwards .1s; }
@keyframes drawLine { to{stroke-dashoffset:0;} }

/* Body: left content, right icon */
.sc-body { display:flex; gap:36px; flex:1; min-height:0; align-items:flex-start; }
.sc-left { flex:1; display:flex; flex-direction:column; gap:12px; overflow:hidden; }
.sc-right {
  width:230px; flex-shrink:0;
  display:flex; flex-direction:column; align-items:center; justify-content:center;
  min-height:340px;
}
.sc-body.full-width .sc-right { display:none; }
.sc-body.full-width .sc-left  { flex:1; }

/* ── BULLET ── */
.wb-bullet {
  display:flex; align-items:flex-start; gap:14px;
  opacity:0; transform:translateX(-40px);
}
.wb-bullet.show { animation:slideIn .52s cubic-bezier(.25,1,.5,1) forwards; }
@keyframes slideIn { to{opacity:1;transform:translateX(0);} }
.bdot {
  width:12px; height:12px; border-radius:50%;
  margin-top:8px; flex-shrink:0;
}
.btext {
  font-size:21px; font-weight:700; line-height:1.55; color:#1e293b;
  /* marker-pen look */
  text-shadow:1px 1px 0 rgba(0,0,0,.05);
}
.btext.em { font-size:24px; font-weight:900; }

/* ── CALLOUT ── */
.wb-callout {
  border-left:5px solid; border-radius:0 10px 10px 0;
  padding:11px 18px; font-size:19px; font-weight:600; line-height:1.5;
  opacity:0; transform:translateX(-40px);
  color:#1e293b;
}
.wb-callout.show { animation:slideIn .52s cubic-bezier(.25,1,.5,1) forwards; }

/* ── WARNING FLASH ── */
.wb-warning {
  display:flex; align-items:center; gap:14px;
  border:2.5px solid #dc2626; border-radius:10px;
  padding:12px 18px; background:rgba(239,68,68,.08);
  opacity:0; transform:scale(.88);
  box-shadow:0 0 0 4px rgba(220,38,38,.10);
}
.wb-warning.show { animation:warnIn .58s cubic-bezier(.34,1.56,.64,1) forwards; }
@keyframes warnIn { to{opacity:1;transform:scale(1);} }
.warn-icon { font-size:34px; flex-shrink:0; }
.warn-text {
  font-size:19px; font-weight:800; color:#b91c1c; line-height:1.4;
}

/* ── STAT ── */
.wb-num {
  display:flex; align-items:center; gap:20px;
  opacity:0; transform:scale(.5);
}
.wb-num.show { animation:numPop .6s cubic-bezier(.34,1.56,.64,1) forwards; }
@keyframes numPop { to{opacity:1;transform:scale(1);} }
.nbadge {
  min-width:90px; height:90px; border-radius:50%; flex-shrink:0;
  display:flex; align-items:center; justify-content:center;
  font-size:26px; font-weight:900; color:#fff;
  box-shadow:3px 3px 0 rgba(0,0,0,.15);
}
.ntext { font-size:19px; font-weight:700; color:#1e293b; line-height:1.5; }

/* ── KEY TERM ── */
.wb-keyterm {
  border-radius:10px; padding:12px 18px;
  border:2px solid; background:rgba(255,255,255,.7);
  opacity:0; transform:translateY(16px);
  box-shadow:2px 3px 0 rgba(0,0,0,.08);
}
.wb-keyterm.show { animation:termIn .52s ease forwards; }
@keyframes termIn { to{opacity:1;transform:translateY(0);} }
.kt-label {
  font-size:11px; font-weight:900; letter-spacing:.12em;
  text-transform:uppercase; margin-bottom:5px;
}
.kt-text { font-size:19px; font-weight:700; color:#1e293b; line-height:1.45; }

/* ── CHECKLIST ── */
.wb-checklist { display:flex; flex-direction:column; gap:8px;
                opacity:0; transform:translateX(-24px); }
.wb-checklist.show { animation:slideIn .5s ease forwards; }
.cl-step {
  display:flex; align-items:center; gap:12px;
  border-radius:8px; padding:8px 14px;
  background:rgba(255,255,255,.75);
  border:1.5px solid rgba(0,0,0,.08);
  opacity:0; transform:translateX(-18px);
  box-shadow:1px 2px 0 rgba(0,0,0,.06);
}
.cl-step.show { animation:slideIn .38s ease forwards; }
.cl-num {
  width:26px; height:26px; border-radius:50%; flex-shrink:0;
  display:flex; align-items:center; justify-content:center;
  font-size:13px; font-weight:900; color:#fff;
}
.cl-text { font-size:18px; font-weight:600; color:#1e293b; line-height:1.3; }

/* ── SCENARIO (split-screen) ── */
.wb-scenario {
  display:flex; gap:14px; flex:1;
  opacity:0; transform:translateY(20px);
}
.wb-scenario.show { animation:scenIn .55s ease forwards; }
@keyframes scenIn { to{opacity:1;transform:translateY(0);} }
.scen-panel {
  flex:1; border-radius:12px; padding:14px 16px;
  display:flex; flex-direction:column; gap:8px;
}
.scen-panel.wrong {
  background:rgba(239,68,68,.09);
  border:2px solid rgba(220,38,38,.5);
}
.scen-panel.right {
  background:rgba(34,197,94,.09);
  border:2px solid rgba(22,163,74,.5);
}
.scen-badge {
  display:inline-flex; align-items:center; gap:7px;
  padding:3px 12px; border-radius:16px;
  font-size:12px; font-weight:900; letter-spacing:.06em;
  text-transform:uppercase; width:fit-content;
}
.scen-badge.wrong { background:rgba(239,68,68,.18); color:#b91c1c; }
.scen-badge.right { background:rgba(34,197,94,.18); color:#15803d; }
.scen-text { font-size:17px; font-weight:700; color:#1e293b; line-height:1.45; }

/* ── ICON (on the whiteboard — pops in like it's being drawn) ── */
.wb-icon {
  display:flex; flex-direction:column; align-items:center; gap:10px;
  opacity:0; transform:scale(.3) rotate(-18deg);
}
.wb-icon.show { animation:iconIn .72s cubic-bezier(.34,1.56,.64,1) forwards; }
@keyframes iconIn {
  60%{opacity:1;transform:scale(1.1) rotate(5deg);}
  to{opacity:1;transform:scale(1) rotate(0);}
}
.wb-icon svg { width:200px; height:200px;
               filter:drop-shadow(2px 3px 0 rgba(0,0,0,.10)); }
.wb-icon .ilbl {
  font-size:14px; font-weight:800; text-align:center; letter-spacing:.06em;
  text-transform:uppercase; padding:4px 14px; border-radius:16px; color:#fff;
}

/* ── MCQ INCOMING HINT ── */
.mcq-hint {
  position:absolute; top:70px; right:20px;
  background:rgba(251,191,36,.15); border:1.5px solid rgba(251,191,36,.7);
  border-radius:20px; padding:5px 15px;
  font-size:11px; font-weight:800; color:#92400e;
  letter-spacing:.07em; text-transform:uppercase;
  opacity:0; animation:mcqHint .4s .3s ease forwards;
  z-index:30;
}
@keyframes mcqHint { to{opacity:1;} }

/* ── CAPTIONS ── */
.caps {
  position:absolute; bottom:0; left:0; right:0; height:96px;
  background:rgba(15,23,42,.91); backdrop-filter:blur(3px);
  display:flex; align-items:center; justify-content:center;
  padding:0 60px; z-index:20;
}
.cap-line  { display:none; font-size:24px; font-weight:600; color:#e2e8f0;
             text-align:center; line-height:1.5; }
.cap-line.active { display:block; }
.cap-word  { padding:0 3px; border-radius:3px; transition:color .1s; }
.cap-word.spoken { color:rgba(148,163,184,.5); }
.cap-word.active { color:#fde68a; font-weight:800; }

/* ── QUESTION CARD (MCQ + True/False overlay) ── */
.q-card {
  position:absolute; inset:0; z-index:40;
  display:flex; align-items:center; justify-content:center;
  background:rgba(10,15,28,.82); backdrop-filter:blur(7px);
  opacity:0; pointer-events:none; transition:opacity .35s ease;
}
.q-card.show { opacity:1; }
.q-inner {
  width:78%; max-width:880px;
  background:linear-gradient(160deg,#ffffff,#f1f5fb);
  border-radius:22px; padding:30px 38px;
  box-shadow:0 24px 70px rgba(0,0,0,.55);
  transform:scale(.86) translateY(24px);
  transition:transform .4s cubic-bezier(.34,1.56,.64,1);
  border:1px solid rgba(255,255,255,.5);
}
.q-card.show .q-inner { transform:scale(1) translateY(0); }
.q-badge {
  display:inline-block; padding:6px 16px; border-radius:20px;
  background:#fde68a; color:#92400e; font-size:13px; font-weight:900;
  letter-spacing:.08em; margin-bottom:16px;
}
.q-question {
  font-size:27px; font-weight:900; color:#0f172a; line-height:1.35;
  margin-bottom:20px;
}
.q-opts { display:flex; flex-direction:column; gap:11px; }
.q-opt {
  display:flex; align-items:center; gap:14px;
  background:#fff; border:2px solid #e2e8f0; border-radius:13px;
  padding:13px 18px; transition:all .3s ease;
}
.q-opt-key {
  width:34px; height:34px; flex-shrink:0; border-radius:9px;
  background:#eef2f7; color:#475569;
  display:flex; align-items:center; justify-content:center;
  font-size:16px; font-weight:900;
}
.q-opt-txt { font-size:20px; font-weight:700; color:#1e293b; flex:1; }
.q-opt-tick {
  font-size:22px; color:#16a34a; font-weight:900; opacity:0;
  transition:opacity .3s ease;
}
/* Reveal phase: correct answer turns green and shows the tick */
.q-card.reveal .q-opt.correct {
  background:rgba(34,197,94,.15); border-color:#16a34a;
  box-shadow:0 0 0 4px rgba(34,197,94,.15);
}
.q-card.reveal .q-opt.correct .q-opt-key { background:#16a34a; color:#fff; }
.q-card.reveal .q-opt.correct .q-opt-tick { opacity:1; }
.q-explain {
  margin-top:18px; padding:13px 18px; border-radius:12px;
  background:#fef9ec; border:1.5px solid #f5d68a;
  font-size:17px; font-weight:600; color:#7c5e10; line-height:1.45;
  opacity:0; transition:opacity .4s ease .2s;
}
.q-card.reveal .q-explain { opacity:1; }
"""

# ── Element renderers ──────────────────────────────────────────────────────


def _render_bullet(el: WBElement, accent: str) -> str:
    color = el.color or accent
    dark = _darken(color)
    emph = " em" if el.emphasis else ""
    return (
        f'<div class="wb-bullet" data-delay="{el.delay:.2f}">'
        f'<div class="bdot" style="background:{color}"></div>'
        f'<div class="btext{emph}" style="color:{dark}">{_e(el.text)}</div>'
        f"</div>"
    )


def _render_callout(el: WBElement, accent: str) -> str:
    color = el.color or accent
    tint = _tint(color, 0.10)
    return (
        f'<div class="wb-callout" data-delay="{el.delay:.2f}" '
        f'style="border-color:{color};background:{tint}">'
        f"{_e(el.text)}"
        f"</div>"
    )


def _render_warning(el: WBElement) -> str:
    return (
        f'<div class="wb-warning" data-delay="{el.delay:.2f}">'
        f'<div class="warn-icon">⚠️</div>'
        f'<div class="warn-text">{_e(el.text)}</div>'
        f"</div>"
    )


def _render_keyterm(el: WBElement, accent: str) -> str:
    color = el.color or accent
    dark = _darken(color)
    return (
        f'<div class="wb-keyterm" data-delay="{el.delay:.2f}" '
        f'style="border-color:{color}">'
        f'<div class="kt-label" style="color:{dark}">Key Term</div>'
        f'<div class="kt-text">{_e(el.text)}</div>'
        f"</div>"
    )


def _render_checklist(el: WBElement, accent: str) -> str:
    color = el.color or accent
    if el.steps:
        steps = el.steps
    elif "|" in el.text:
        steps = [s.strip() for s in el.text.split("|") if s.strip()]
    else:
        steps = [el.text]

    steps_html = ""
    for i, step in enumerate(steps):
        step_delay = el.delay + i * 0.38
        steps_html += (
            f'<div class="cl-step" data-delay="{step_delay:.2f}">'
            f'<div class="cl-num" style="background:{color}">{i+1}</div>'
            f'<div class="cl-text">{_e(step)}</div>'
            f"</div>"
        )
    return (
        f'<div class="wb-checklist" data-delay="{el.delay:.2f}">'
        f"{steps_html}"
        f"</div>"
    )


def _render_stat(el: WBElement, accent: str) -> str:
    color = el.color or accent
    val = _e(el.stat_value or "?")
    return (
        f'<div class="wb-num" data-delay="{el.delay:.2f}">'
        f'<div class="nbadge" style="background:{color}">{val}</div>'
        f'<div class="ntext">{_e(el.text)}</div>'
        f"</div>"
    )


def _render_scenario(el: WBElement) -> str:
    wrong = _e(el.wrong_action or "Incorrect action")
    right = _e(el.correct_action or "Correct safe action")
    return (
        f'<div class="wb-scenario" data-delay="{el.delay:.2f}">'
        f'<div class="scen-panel wrong">'
        f'<div class="scen-badge wrong">❌ &nbsp;Wrong</div>'
        f'<div class="scen-text">{wrong}</div>'
        f"</div>"
        f'<div class="scen-panel right">'
        f'<div class="scen-badge right">✅ &nbsp;Correct</div>'
        f'<div class="scen-text">{right}</div>'
        f"</div>"
        f"</div>"
    )


def _render_icon(el: WBElement, accent: str) -> str:
    color = el.color or accent
    # For whiteboard style prefer coloured icons over line-art
    svg = get_illustration(el.icon_query, color=color, line=False)
    if not svg:
        svg = get_illustration(el.icon_query, color=color, line=True)
    if not svg:
        return ""
    label = _e(el.text or el.icon_query.split()[-1].title())
    return (
        f'<div class="wb-icon" data-delay="{el.delay:.2f}">'
        f"{svg}"
        f'<div class="ilbl" style="background:{color}">{label}</div>'
        f"</div>"
    )


# ── Scene renderer ─────────────────────────────────────────────────────────


def _render_scene(
    idx: int, scene: WBScene, t_start: float,
    mcq_after: set[int]
) -> str:
    accent = scene.accent_color or "#2563eb"
    tint = _tint(accent, 0.05)

    left_parts: list[str] = []
    icon_html = ""

    for el in scene.elements:
        t = el.type
        if t == "icon":
            if not icon_html:
                icon_html = _render_icon(el, accent)
        elif t == "bullet":
            left_parts.append(_render_bullet(el, accent))
        elif t == "callout":
            left_parts.append(_render_callout(el, accent))
        elif t == "warning_flash":
            left_parts.append(_render_warning(el))
        elif t == "key_term":
            left_parts.append(_render_keyterm(el, accent))
        elif t == "checklist":
            left_parts.append(_render_checklist(el, accent))
        elif t == "stat":
            left_parts.append(_render_stat(el, accent))
        elif t == "scenario":
            left_parts.append(_render_scenario(el))
        elif t == "question_pop":
            left_parts.append(_render_callout(el, "#f59e0b"))

    full_width = "full-width" if not icon_html else ""
    right_col = f'<div class="sc-right">{icon_html}</div>' if icon_html else ""
    left_html = "\n".join(left_parts)

    # Wavy underline (hand-drawn style)
    ul_w = max(120, min(680, len(scene.title) * 22))
    ul_svg = (
        f'<svg class="uline" viewBox="0 0 680 20" preserveAspectRatio="none" '
        f'style="width:{ul_w}px;height:13px">'
        f'<path class="uline-path" data-delay="0.22" stroke="{accent}" '
        f'd="M0 10 Q85 2 170 10 Q255 18 340 10 Q425 2 510 10 Q595 18 680 10"/>'
        f"</svg>"
    )

    mcq_hint = ""
    if idx in mcq_after:
        mcq_hint = '<div class="mcq-hint">⏸ Knowledge Check</div>'

    return f"""
<div class="scene" data-scene="{idx}" data-start="{t_start:.3f}"
     style="background:{tint}">
  {mcq_hint}
  <div>
    <span class="sc-title" data-delay="0.04" style="color:{accent}">{_e(scene.title)}</span>
    {ul_svg}
  </div>
  <div class="sc-body {full_width}">
    <div class="sc-left">
      {left_html}
    </div>
    {right_col}
  </div>
</div>"""


# ── Captions ───────────────────────────────────────────────────────────────


def _build_captions(words: list[dict]) -> str:
    groups = _caption_groups(words)
    lines = []
    for gi, g in enumerate(groups):
        spans = "".join(
            f'<span class="cap-word" data-start="{w["start"]:.3f}" '
            f'data-end="{w["end"]:.3f}">{_e(w["word"])} </span>'
            for w in g["words"]
        )
        lines.append(
            f'<div class="cap-line" data-line="{gi}" '
            f'data-start="{g["start"]:.3f}" data-end="{g["end"]:.3f}">{spans}</div>'
        )
    return "\n".join(lines)


# ── Question cards (MCQ + True/False shown in-video) ───────────────────────


def _build_question_cards(quiz_data: list[dict]) -> str:
    """Build full-screen question-card overlays, one per question."""
    if not quiz_data:
        return ""
    cards = []
    letters = ["A", "B", "C", "D"]
    for qi, q in enumerate(quiz_data):
        kind = q.get("kind", "mcq")
        correct = q.get("correct_index", 0)
        opts = q.get("options") or (["True", "False"] if kind == "true_false" else [])
        opts_html = ""
        for oi, opt in enumerate(opts):
            is_correct = "correct" if oi == correct else ""
            if kind == "true_false":
                label = "T" if oi == 0 else "F"
            else:
                label = letters[oi] if oi < 4 else "•"
            opts_html += (
                f'<div class="q-opt {is_correct}" data-correct="{1 if oi == correct else 0}">'
                f'<span class="q-opt-key">{label}</span>'
                f'<span class="q-opt-txt">{_e(opt)}</span>'
                f'<span class="q-opt-tick">✓</span>'
                f"</div>"
            )
        expl = _e(q.get("explanation", ""))
        expl_html = (
            f'<div class="q-explain">💡 {expl}</div>' if expl else ""
        )
        badge = "TRUE / FALSE" if kind == "true_false" else "QUICK QUESTION"
        cards.append(
            f'<div class="q-card" data-qcard="{qi}" '
            f'data-ts="{q.get("timestamp", 0):.2f}">'
            f'<div class="q-inner">'
            f'<div class="q-badge">❓ {badge}</div>'
            f'<div class="q-question">{_e(q.get("question", ""))}</div>'
            f'<div class="q-opts">{opts_html}</div>'
            f"{expl_html}"
            f"</div></div>"
        )
    return "\n".join(cards)


# ── Main HTML builder ──────────────────────────────────────────────────────


def render_whiteboard_html(
    lesson_title: str,
    plan: WhiteboardPlan,
    words: list[dict],
    dur: float,
    questions: list | None = None,
    mcqs: list | None = None,   # legacy alias
) -> str:
    """Return a 1280×720 self-playing whiteboard HTML page for Playwright to record.

    `questions` is a list of Question objects (kind='mcq' or 'true_false').
    If empty/None, the video simply has no question cards — never an error.
    """
    questions = questions or mcqs or []
    timings = _compute_scene_timings(plan.scenes, dur)
    first_accent = plan.scenes[0].accent_color if plan.scenes else "#2563eb"

    # Which scenes have a question after them (for the "Knowledge Check" hint badge)
    q_after: set[int] = set()
    for q in questions:
        try:
            q_after.add(int(getattr(q, "after_scene", 0)))
        except Exception:
            pass

    scenes_html = "\n".join(
        _render_scene(i, s, t_start, q_after)
        for i, (s, (t_start, _)) in enumerate(zip(plan.scenes, timings))
    )
    captions_html = _build_captions(words)

    scene_data = [{"start": t, "end": e} for t, e in timings]
    scene_data_json = json.dumps(scene_data)
    total = len(plan.scenes)
    finish = dur + 1.5

    # Build structured quiz data (both MCQ + True/False) for the frontend AND
    # for the in-video question cards. Empty list if no questions.
    quiz_data: list[dict] = []
    for q in questions:
        try:
            kind = getattr(q, "kind", "mcq")
            si = int(getattr(q, "after_scene", 0))
            trigger_time = timings[si][1] if si < len(timings) else dur
            opts = list(getattr(q, "options", []) or [])
            if kind == "true_false" and not opts:
                opts = ["True", "False"]
            quiz_data.append({
                "kind": kind,
                "timestamp": round(trigger_time, 2),
                "question": getattr(q, "question", ""),
                "options": opts,
                "correct_index": int(getattr(q, "correct_index", 0)),
                "explanation": getattr(q, "explanation", ""),
            })
        except Exception:
            pass
    quiz_json = json.dumps(quiz_data, ensure_ascii=False)
    # legacy id kept for any existing frontend code
    mcq_json = quiz_json

    question_cards_html = _build_question_cards(quiz_data)

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>{_CSS}</style>
</head>
<body>
<div id="stage">

  <!-- Whiteboard header -->
  <div class="wb-hdr" id="hdr" style="border-color:{first_accent}">
    <h1>{_e(lesson_title)}</h1>
    <span class="snum" id="snum">1 / {total}</span>
  </div>

  <!-- Hand with marker — always visible, bobs while content draws -->
  <div class="hand-marker" id="hand">✍️</div>

  <!-- Marker tray at the bottom of the board -->
  <div id="tray"></div>

  <!-- Scenes -->
  {scenes_html}

  <!-- Question cards (MCQ + True/False) shown over the video -->
  {question_cards_html}

  <!-- Karaoke captions -->
  <div class="caps">{captions_html}</div>
</div>

<!-- Quiz metadata for the frontend (both mcq + true_false) -->
<script type="application/json" id="quiz-data">{quiz_json}</script>
<script type="application/json" id="mcq-data">{mcq_json}</script>

<script>
const SCENES = {scene_data_json};
const TOTAL  = {total};
let t0 = null, curScene = -1;

function getSceneEl(i) {{
  return document.querySelector('[data-scene="' + i + '"]');
}}

function activateScene(si) {{
  const el = getSceneEl(si);
  if (!el) return;
  el.classList.remove('leaving');
  el.classList.add('active', 'entering');
  document.getElementById('snum').textContent = (si+1) + ' / ' + TOTAL;
  // Update header accent colour to match current scene
  const title = el.querySelector('.sc-title');
  if (title) {{
    document.getElementById('hdr').style.borderColor = title.style.color;
  }}
  setTimeout(() => el.classList.remove('entering'), 540);
}}

function deactivateScene(si) {{
  const el = getSceneEl(si);
  if (!el) return;
  el.classList.add('leaving');
  el.classList.remove('active','entering');
  setTimeout(() => el.classList.remove('leaving'), 400);
}}

function frame(ts) {{
  if (t0 === null) t0 = ts;
  const t = (ts - t0) / 1000;

  // Current scene
  let si = -1;
  for (let i = 0; i < SCENES.length; i++) {{
    if (t >= SCENES[i].start) si = i;
  }}

  if (si !== curScene) {{
    if (curScene >= 0) deactivateScene(curScene);
    if (si >= 0)       activateScene(si);
    curScene = si;
  }}

  // Animate elements
  if (si >= 0) {{
    const sceneEl = getSceneEl(si);
    if (sceneEl) {{
      const elapsed = t - SCENES[si].start;
      let anyDrawing = false;
      sceneEl.querySelectorAll('[data-delay]').forEach(el => {{
        const d = +el.dataset.delay;
        if (elapsed >= d) {{
          el.classList.add('show');
        }} else if (elapsed >= d - 0.25) {{
          anyDrawing = true;
        }}
      }});
      // Make hand "write" when content is actively drawing in
      document.getElementById('hand').classList.toggle('writing', anyDrawing);
    }}
  }}

  // Karaoke
  document.querySelectorAll('.cap-line').forEach(l => {{
    const s = +l.dataset.start, e = +l.dataset.end;
    l.classList.toggle('active', t >= s - 0.25 && t <= e + 0.6);
  }});
  document.querySelectorAll('.cap-word').forEach(w => {{
    const s = +w.dataset.start, e = +w.dataset.end;
    w.classList.toggle('spoken', t > e);
    w.classList.toggle('active',  t >= s && t <= e);
  }});

  // Question cards: show for a 5s window from their timestamp;
  // reveal the correct answer 2.4s in.
  document.querySelectorAll('.q-card').forEach(card => {{
    const ts = +card.dataset.ts;
    const shown   = t >= ts && t <= ts + 5.0;
    const reveal  = t >= ts + 2.4 && t <= ts + 5.0;
    card.classList.toggle('show', shown);
    card.classList.toggle('reveal', reveal);
  }});

  if (t < {finish}) requestAnimationFrame(frame);
  else window.__done = true;
}}

window.__done = false;
window.addEventListener('load', () => requestAnimationFrame(frame));
</script>
</body></html>"""
