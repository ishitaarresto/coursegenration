"""Cinematic dark animated video HTML generator.

Converts a WhiteboardPlan into a self-playing HTML page that Playwright
records to WebM. Visual style:
  - Dark cinematic backgrounds matched to environment (road, warehouse, construction...)
  - Bold full-screen objects / tool icons (Iconify SVGs, large)
  - Split-screen SCENARIO panels: ❌ wrong action  vs  ✅ correct action
  - WARNING_FLASH: dramatic red pulse for critical safety rules
  - CHECKLIST: step-by-step animated tick list
  - KEY_TERM: bold definition card
  - STAT: giant impact number
  - MCQ pause marker: subtle "⏸ Knowledge Check incoming" hint
  - Karaoke captions at the bottom
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


# Background themes — dark gradients matching the physical environment
_BG_THEMES: dict[str, str] = {
    "dark_road":
        "radial-gradient(ellipse at 20% 60%, #1a2535 0%, #0d1117 60%),"
        "linear-gradient(180deg, #0d1117 0%, #111827 100%)",
    "dark_construction":
        "radial-gradient(ellipse at 80% 30%, #1c1408 0%, #0d0f0a 70%),"
        "linear-gradient(180deg, #111006 0%, #0d1117 100%)",
    "dark_warehouse":
        "radial-gradient(ellipse at 50% 20%, #0f1a20 0%, #060c10 80%),"
        "linear-gradient(180deg, #07111a 0%, #0d1117 100%)",
    "dark_industrial":
        "radial-gradient(ellipse at 30% 70%, #180d0d 0%, #0d0d0d 70%),"
        "linear-gradient(180deg, #130f0a 0%, #0d1117 100%)",
    "dark_office":
        "radial-gradient(ellipse at 70% 40%, #0d1230 0%, #080a1a 70%),"
        "linear-gradient(180deg, #0a0d22 0%, #0d1117 100%)",
    "cinematic_dark":
        "radial-gradient(ellipse at 50% 50%, #14141e 0%, #0a0a0f 100%),"
        "linear-gradient(135deg, #0a0a0f 0%, #111117 100%)",
}


def _bg(theme: str) -> str:
    return _BG_THEMES.get(theme, _BG_THEMES["cinematic_dark"])


# ── CSS ────────────────────────────────────────────────────────────────────

_CSS = r"""
* { margin:0; padding:0; box-sizing:border-box; }
body { width:1280px; height:720px; overflow:hidden;
       font-family:'Segoe UI',system-ui,Arial,sans-serif; }

#stage {
  position:relative; width:1280px; height:720px;
}

/* ─── HEADER ─── */
.wb-hdr {
  position:absolute; top:0; left:0; right:0; height:64px;
  display:flex; align-items:center; padding:0 44px; z-index:10;
  background:rgba(0,0,0,.55); backdrop-filter:blur(6px);
  border-bottom:2px solid rgba(255,255,255,.08);
}
.wb-hdr h1 {
  color:#f1f5f9; font-size:22px; font-weight:800; flex:1;
  white-space:nowrap; overflow:hidden; text-overflow:ellipsis;
  letter-spacing:.02em;
}
.wb-hdr .snum {
  color:rgba(255,255,255,.45); font-size:12px; font-weight:600;
  letter-spacing:.08em; text-transform:uppercase;
}

/* ─── ACCENT LINE beneath header ─── */
.accent-line {
  position:absolute; top:64px; left:0; right:0; height:3px;
  transition:background .6s;
}

/* ─── SCENES ─── */
.scene {
  position:absolute; top:67px; left:0; right:0; bottom:96px;
  padding:20px 52px 14px;
  display:flex; flex-direction:column; gap:12px;
  opacity:0; pointer-events:none;
}
.scene.active   { opacity:1; pointer-events:auto; }
.scene.entering { animation:sceneIn .5s ease forwards; }
.scene.leaving  { animation:sceneOut .38s ease forwards; pointer-events:none; }
@keyframes sceneIn  { from{opacity:0;transform:translateX(55px);}
                       to{opacity:1;transform:translateX(0);} }
@keyframes sceneOut { from{opacity:1;transform:translateX(0);}
                       to{opacity:0;transform:translateX(-40px);} }

/* Scene title */
.sc-title {
  font-size:36px; font-weight:900; line-height:1.2;
  text-transform:uppercase; letter-spacing:.04em;
  opacity:0; transform:translateY(-16px);
  text-shadow:0 2px 20px rgba(0,0,0,.6);
}
.sc-title.show { animation:titleIn .48s ease forwards; }
@keyframes titleIn { to{opacity:1;transform:translateY(0);} }

/* Glowing underline bar */
.sc-bar {
  height:4px; border-radius:4px; width:0; margin-top:2px; margin-bottom:8px;
  opacity:0;
}
.sc-bar.show { animation:barIn .55s ease forwards; }
@keyframes barIn { to{opacity:1;width:100%;} }

/* Body split: left content / right icon */
.sc-body { display:flex; gap:40px; flex:1; min-height:0; align-items:flex-start; }
.sc-left { flex:1; display:flex; flex-direction:column; gap:14px; overflow:hidden; }
.sc-right {
  width:240px; flex-shrink:0;
  display:flex; flex-direction:column; align-items:center; justify-content:center;
  min-height:360px;
}
.sc-body.full-width .sc-right { display:none; }
.sc-body.full-width .sc-left  { flex:1; }

/* ─── BULLET ─── */
.wb-bullet {
  display:flex; align-items:flex-start; gap:14px;
  opacity:0; transform:translateX(-44px);
}
.wb-bullet.show { animation:slideIn .52s cubic-bezier(.25,1,.5,1) forwards; }
@keyframes slideIn { to{opacity:1;transform:translateX(0);} }
.bdot {
  width:10px; height:10px; border-radius:50%;
  margin-top:10px; flex-shrink:0;
  box-shadow:0 0 8px currentColor;
}
.btext { font-size:21px; font-weight:600; line-height:1.55; color:#e2e8f0; }
.btext.em { font-size:24px; font-weight:800; color:#fff; }

/* ─── CALLOUT ─── */
.wb-callout {
  border-left:5px solid; border-radius:0 12px 12px 0;
  padding:13px 20px; font-size:19px; font-weight:600; line-height:1.5;
  opacity:0; transform:translateX(-44px);
  backdrop-filter:blur(4px);
}
.wb-callout.show { animation:slideIn .52s cubic-bezier(.25,1,.5,1) forwards; }

/* ─── WARNING FLASH ─── */
.wb-warning {
  display:flex; align-items:center; gap:16px;
  background:rgba(239,68,68,.18); border:2px solid #ef4444;
  border-radius:12px; padding:14px 20px;
  opacity:0; transform:scale(.88);
  box-shadow:0 0 24px rgba(239,68,68,.35), inset 0 0 30px rgba(239,68,68,.08);
}
.wb-warning.show { animation:warnIn .6s cubic-bezier(.34,1.56,.64,1) forwards; }
@keyframes warnIn { to{opacity:1;transform:scale(1);} }
.warn-icon { font-size:36px; flex-shrink:0; filter:drop-shadow(0 0 8px #ef4444); }
.warn-text {
  font-size:20px; font-weight:800; color:#fca5a5; line-height:1.4;
  text-shadow:0 1px 8px rgba(239,68,68,.4);
}

/* ─── STAT ─── */
.wb-num {
  display:flex; align-items:center; gap:22px;
  opacity:0; transform:scale(.5);
}
.wb-num.show { animation:numPop .62s cubic-bezier(.34,1.56,.64,1) forwards; }
@keyframes numPop { to{opacity:1;transform:scale(1);} }
.nbadge {
  min-width:96px; height:96px; border-radius:50%; flex-shrink:0;
  display:flex; align-items:center; justify-content:center;
  font-size:28px; font-weight:900; color:#fff;
  box-shadow:0 0 30px rgba(0,0,0,.5), 0 0 16px currentColor;
}
.ntext { font-size:20px; font-weight:700; color:#e2e8f0; line-height:1.5; }

/* ─── KEY TERM ─── */
.wb-keyterm {
  border-radius:12px; padding:14px 20px;
  border:1.5px solid rgba(255,255,255,.15);
  background:rgba(255,255,255,.07); backdrop-filter:blur(6px);
  opacity:0; transform:translateY(20px);
}
.wb-keyterm.show { animation:termIn .55s ease forwards; }
@keyframes termIn { to{opacity:1;transform:translateY(0);} }
.kt-label { font-size:12px; font-weight:800; letter-spacing:.1em;
            text-transform:uppercase; color:rgba(255,255,255,.5); margin-bottom:6px; }
.kt-text  { font-size:20px; font-weight:700; color:#e2e8f0; line-height:1.5; }

/* ─── CHECKLIST ─── */
.wb-checklist { display:flex; flex-direction:column; gap:9px;
                opacity:0; transform:translateX(-30px); }
.wb-checklist.show { animation:slideIn .55s ease forwards; }
.cl-step {
  display:flex; align-items:center; gap:12px;
  background:rgba(255,255,255,.06); border-radius:10px; padding:9px 16px;
  opacity:0; transform:translateX(-20px);
}
.cl-step.show { animation:slideIn .4s ease forwards; }
.cl-num {
  width:28px; height:28px; border-radius:50%; flex-shrink:0;
  display:flex; align-items:center; justify-content:center;
  font-size:13px; font-weight:900; color:#fff;
}
.cl-text { font-size:18px; font-weight:600; color:#e2e8f0; line-height:1.35; }

/* ─── SCENARIO (split-screen) ─── */
.wb-scenario {
  display:flex; gap:12px; flex:1;
  opacity:0; transform:translateY(24px);
}
.wb-scenario.show { animation:scenIn .58s ease forwards; }
@keyframes scenIn { to{opacity:1;transform:translateY(0);} }
.scen-panel {
  flex:1; border-radius:14px; padding:16px 18px;
  display:flex; flex-direction:column; gap:10px;
}
.scen-panel.wrong {
  background:rgba(239,68,68,.14); border:2px solid rgba(239,68,68,.55);
  box-shadow:0 0 20px rgba(239,68,68,.15);
}
.scen-panel.right {
  background:rgba(34,197,94,.14); border:2px solid rgba(34,197,94,.55);
  box-shadow:0 0 20px rgba(34,197,94,.15);
}
.scen-badge {
  display:inline-flex; align-items:center; gap:8px;
  padding:4px 14px; border-radius:20px; font-size:13px; font-weight:800;
  letter-spacing:.06em; text-transform:uppercase; width:fit-content;
}
.scen-badge.wrong { background:rgba(239,68,68,.3); color:#fca5a5; }
.scen-badge.right { background:rgba(34,197,94,.3); color:#86efac; }
.scen-text { font-size:18px; font-weight:700; color:#e2e8f0; line-height:1.5; }

/* ─── ICON ─── */
.wb-icon {
  display:flex; flex-direction:column; align-items:center; gap:12px;
  opacity:0; transform:scale(.35) rotate(-20deg);
}
.wb-icon.show { animation:iconIn .75s cubic-bezier(.34,1.56,.64,1) forwards; }
@keyframes iconIn {
  60%{opacity:1;transform:scale(1.1) rotate(5deg);}
  to{opacity:1;transform:scale(1) rotate(0);}
}
.wb-icon svg { width:210px; height:210px; filter:drop-shadow(0 0 18px rgba(255,255,255,.15)); }
.wb-icon .ilbl {
  font-size:14px; font-weight:800; text-align:center; letter-spacing:.06em;
  text-transform:uppercase; padding:5px 16px; border-radius:20px; color:#fff;
}

/* ─── MCQ HINT (pause marker) ─── */
.mcq-hint {
  position:absolute; top:72px; right:18px;
  background:rgba(251,191,36,.18); border:1.5px solid rgba(251,191,36,.6);
  border-radius:24px; padding:6px 16px;
  font-size:12px; font-weight:800; color:#fde68a;
  letter-spacing:.06em; text-transform:uppercase;
  opacity:0; animation:mcqHint .4s .2s ease forwards;
  z-index:30;
}
@keyframes mcqHint { to{opacity:1;} }

/* ─── CAPTIONS ─── */
.caps {
  position:absolute; bottom:0; left:0; right:0; height:96px;
  background:rgba(7,10,18,.92); backdrop-filter:blur(4px);
  display:flex; align-items:center; justify-content:center;
  padding:0 60px; z-index:20;
  border-top:1.5px solid rgba(255,255,255,.07);
}
.cap-line  { display:none; font-size:24px; font-weight:600; color:#cbd5e1;
             text-align:center; line-height:1.5; }
.cap-line.active { display:block; }
.cap-word  { padding:0 3px; border-radius:4px; transition:color .1s; }
.cap-word.spoken { color:rgba(148,163,184,.55); }
.cap-word.active { color:#fde68a; font-weight:800; }
"""

# ── Element renderers ──────────────────────────────────────────────────────


def _render_bullet(el: WBElement, accent: str) -> str:
    color = el.color or accent
    emph = " em" if el.emphasis else ""
    return (
        f'<div class="wb-bullet" data-delay="{el.delay:.2f}">'
        f'<div class="bdot" style="background:{color};color:{color}"></div>'
        f'<div class="btext{emph}">{_e(el.text)}</div>'
        f"</div>"
    )


def _render_callout(el: WBElement, accent: str) -> str:
    color = el.color or accent
    # Semi-transparent background
    return (
        f'<div class="wb-callout" data-delay="{el.delay:.2f}" '
        f'style="border-color:{color};background:rgba(0,0,0,.35);color:#e2e8f0">'
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
    return (
        f'<div class="wb-keyterm" data-delay="{el.delay:.2f}" '
        f'style="border-color:{color}55">'
        f'<div class="kt-label" style="color:{color}">Key Term</div>'
        f'<div class="kt-text">{_e(el.text)}</div>'
        f"</div>"
    )


def _render_checklist(el: WBElement, accent: str) -> str:
    color = el.color or accent
    # Steps can come from el.steps (list) or el.text (pipe-separated)
    if el.steps:
        steps = el.steps
    elif "|" in el.text:
        steps = [s.strip() for s in el.text.split("|") if s.strip()]
    else:
        steps = [el.text]

    steps_html = ""
    for i, step in enumerate(steps):
        step_delay = el.delay + i * 0.35
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
        f'<div class="nbadge" style="background:{color};color:{color}">'
        f'<span style="color:#fff">{val}</span></div>'
        f'<div class="ntext">{_e(el.text)}</div>'
        f"</div>"
    )


def _render_scenario(el: WBElement) -> str:
    wrong = _e(el.wrong_action or "Incorrect action")
    right = _e(el.correct_action or "Correct safe action")
    return (
        f'<div class="wb-scenario" data-delay="{el.delay:.2f}">'
        # Wrong panel
        f'<div class="scen-panel wrong">'
        f'<div class="scen-badge wrong">❌ &nbsp;Wrong</div>'
        f'<div class="scen-text">{wrong}</div>'
        f"</div>"
        # Right panel
        f'<div class="scen-panel right">'
        f'<div class="scen-badge right">✅ &nbsp;Correct</div>'
        f'<div class="scen-text">{right}</div>'
        f"</div>"
        f"</div>"
    )


def _render_icon(el: WBElement, accent: str) -> str:
    color = el.color or accent
    svg = get_illustration(el.icon_query, color=color, line=False)
    if not svg:
        svg = get_illustration(el.icon_query, color=color, line=True)
    if not svg:
        return ""
    label = _e(el.text or el.icon_query.split()[-1].title())
    return (
        f'<div class="wb-icon" data-delay="{el.delay:.2f}">'
        f"{svg}"
        f'<div class="ilbl" style="background:{color}aa">{label}</div>'
        f"</div>"
    )


# ── Scene renderer ─────────────────────────────────────────────────────────


def _render_scene(
    idx: int, scene: WBScene, t_start: float,
    mcq_after: set[int]
) -> str:
    accent = scene.accent_color or "#3b82f6"
    bg = _bg(getattr(scene, "bg_theme", "cinematic_dark"))

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
            # Scenario takes full width — force no right icon for this element
            left_parts.append(_render_scenario(el))
        # legacy fallback
        elif t == "question_pop":
            left_parts.append(_render_callout(el, "#f59e0b"))

    full_width = "full-width" if not icon_html else ""
    right_col = f'<div class="sc-right">{icon_html}</div>' if icon_html else ""
    left_html = "\n".join(left_parts)

    # MCQ incoming hint badge
    mcq_hint = ""
    if idx in mcq_after:
        mcq_hint = '<div class="mcq-hint">⏸ Knowledge Check</div>'

    return f"""
<div class="scene" data-scene="{idx}" data-start="{t_start:.3f}"
     style="background:{bg}">
  {mcq_hint}
  <span class="sc-title" data-delay="0.05" style="color:{accent}">{_e(scene.title)}</span>
  <div class="sc-bar" data-delay="0.22" style="background:{accent};box-shadow:0 0 12px {accent}88"></div>
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


# ── Main HTML builder ──────────────────────────────────────────────────────


def render_whiteboard_html(
    lesson_title: str,
    plan: WhiteboardPlan,
    words: list[dict],
    dur: float,
) -> str:
    """Return a 1280×720 self-playing cinematic HTML page for Playwright to record."""
    timings = _compute_scene_timings(plan.scenes, dur)

    first_accent = plan.scenes[0].accent_color if plan.scenes else "#3b82f6"

    # Build set of scene indices after which an MCQ fires
    mcq_after: set[int] = set()
    if hasattr(plan, "mcqs") and plan.mcqs:
        for mcq in plan.mcqs:
            mcq_after.add(mcq.after_scene)

    scenes_html = "\n".join(
        _render_scene(i, s, t_start, mcq_after)
        for i, (s, (t_start, _)) in enumerate(zip(plan.scenes, timings))
    )
    captions_html = _build_captions(words)

    scene_data = [{"start": t, "end": e} for t, e in timings]
    scene_data_json = json.dumps(scene_data)
    total = len(plan.scenes)
    finish = dur + 1.5

    # MCQ data for frontend consumption (embedded in page as metadata)
    mcq_data: list[dict] = []
    if hasattr(plan, "mcqs") and plan.mcqs:
        for mcq in plan.mcqs:
            si = mcq.after_scene
            trigger_time = timings[si][1] if si < len(timings) else dur
            mcq_data.append({
                "timestamp": round(trigger_time, 2),
                "question": mcq.question,
                "options": mcq.options,
                "correct_index": mcq.correct_index,
                "explanation": mcq.explanation,
            })

    mcq_json = json.dumps(mcq_data)

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>{_CSS}</style>
</head>
<body>
<div id="stage">
  <!-- Header -->
  <div class="wb-hdr">
    <h1>{_e(lesson_title)}</h1>
    <span class="snum" id="snum">1 / {total}</span>
  </div>
  <div class="accent-line" id="aline" style="background:{first_accent}"></div>

  <!-- Scenes -->
  {scenes_html}

  <!-- Karaoke captions -->
  <div class="caps">{captions_html}</div>
</div>

<!-- MCQ metadata for frontend -->
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
  document.getElementById('snum').textContent = (si + 1) + ' / ' + TOTAL;
  // Update accent line color
  const title = el.querySelector('.sc-title');
  if (title) {{
    document.getElementById('aline').style.background = title.style.color;
  }}
  setTimeout(() => el.classList.remove('entering'), 550);
}}

function deactivateScene(si) {{
  const el = getSceneEl(si);
  if (!el) return;
  el.classList.add('leaving');
  el.classList.remove('active', 'entering');
  setTimeout(() => el.classList.remove('leaving'), 420);
}}

function frame(ts) {{
  if (t0 === null) t0 = ts;
  const t = (ts - t0) / 1000;

  // Determine current scene
  let si = -1;
  for (let i = 0; i < SCENES.length; i++) {{
    if (t >= SCENES[i].start) si = i;
  }}

  // Scene transitions
  if (si !== curScene) {{
    if (curScene >= 0) deactivateScene(curScene);
    if (si >= 0)       activateScene(si);
    curScene = si;
  }}

  // Animate elements inside current scene
  if (si >= 0) {{
    const sceneEl = getSceneEl(si);
    if (sceneEl) {{
      const elapsed = t - SCENES[si].start;
      sceneEl.querySelectorAll('[data-delay]').forEach(el => {{
        if (elapsed >= +el.dataset.delay) el.classList.add('show');
      }});
    }}
  }}

  // Karaoke captions
  document.querySelectorAll('.cap-line').forEach(l => {{
    const s = +l.dataset.start, e = +l.dataset.end;
    l.classList.toggle('active', t >= s - 0.25 && t <= e + 0.6);
  }});
  document.querySelectorAll('.cap-word').forEach(w => {{
    const s = +w.dataset.start, e = +w.dataset.end;
    w.classList.toggle('spoken', t > e);
    w.classList.toggle('active',  t >= s && t <= e);
  }});

  if (t < {finish}) requestAnimationFrame(frame);
  else window.__done = true;
}}

window.__done = false;
window.addEventListener('load', () => requestAnimationFrame(frame));
</script>
</body></html>"""
