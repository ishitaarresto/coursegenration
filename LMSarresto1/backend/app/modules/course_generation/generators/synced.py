"""Word-synced animated video builder.

Pops the matching illustration on screen exactly when its keyword is spoken,
with karaoke-style captions. Driven by per-word timings from edge-tts.
"""
from __future__ import annotations

import html
import json

from app.modules.course_generation.generators.assets import get_illustration

# Concept keyword -> illustration search query. Plurals handled automatically.
KEYWORD_QUERIES = {
    "helmet": "helmet", "bicycle": "bicycle", "bike": "bicycle", "cyclist": "bicycle",
    "car": "car", "vehicle": "car", "driver": "steering wheel", "truck": "truck",
    "pedestrian": "pedestrian", "walking": "person walking", "crossing": "pedestrian crossing",
    "crosswalk": "pedestrian crossing", "footpath": "sidewalk", "sidewalk": "sidewalk",
    "road": "road", "traffic": "traffic light", "light": "traffic light", "lights": "traffic light",
    "signal": "traffic light", "reflective": "reflective vest", "visible": "eye",
    "visibility": "eye", "night": "moon night", "dark": "moon night",
    "eye": "eye", "contact": "eye", "mirror": "car mirror", "brake": "brake",
    "speed": "speedometer", "speeding": "speedometer", "fast": "speedometer",
    "distraction": "smartphone", "phone": "smartphone", "fatigue": "sleeping",
    "tired": "sleeping", "sleep": "sleeping", "alcohol": "alcohol drink",
    "impairment": "alcohol drink", "seatbelt": "seatbelt", "belt": "seatbelt",
    "fire": "fire", "flame": "fire", "smoke": "smoke", "extinguisher": "fire extinguisher",
    "alarm": "alarm bell", "exit": "exit door", "evacuate": "exit door",
    "evacuation": "exit door", "emergency": "siren", "hazard": "warning",
    "danger": "warning", "warning": "warning", "electrical": "electric plug",
    "chemical": "chemical hazard", "spill": "spill", "ladder": "ladder",
    "height": "ladder", "gloves": "safety gloves", "ppe": "safety helmet",
    "oxygen": "oxygen", "heat": "fire", "fuel": "fuel", "muster": "meeting point",
    "warden": "guard", "first": "first aid", "aid": "first aid",
}


def _e(s: str) -> str:
    return html.escape(s or "")


def _norm(word: str) -> str:
    w = word.lower().strip(".,!?;:'\"()")
    if w.endswith("s") and w[:-1] in KEYWORD_QUERIES:
        return w[:-1]
    return w


def build_cues(words: list[dict], color: str = "#2563eb", max_cues: int = 24) -> list[dict]:
    """Scan word timeline; for each matched keyword, fetch an illustration cue."""
    cues: list[dict] = []
    last_concept = ""
    last_time = -10.0
    svg_cache: dict[str, str] = {}

    for w in words:
        concept = _norm(w["word"])
        query = KEYWORD_QUERIES.get(concept)
        if not query:
            continue
        # avoid repeating same concept within 4s
        if concept == last_concept and (w["start"] - last_time) < 4.0:
            continue
        if query not in svg_cache:
            svg_cache[query] = get_illustration(query, color=color)
        svg = svg_cache[query]
        if not svg:
            continue
        cues.append({"start": w["start"], "label": w["word"].strip(".,!?;:"), "svg": svg})
        last_concept = concept
        last_time = w["start"]
        if len(cues) >= max_cues:
            break
    return cues


def cluster_cues(cues: list[dict], max_per_cluster: int = 3, gap: float = 5.5) -> list[list[dict]]:
    """Group cues so 2-3 illustrations build up together, then clear for the next set.

    A new cluster starts when the current one is full OR there's a speaking gap.
    """
    clusters: list[list[dict]] = []
    cur: list[dict] = []
    for c in cues:
        if cur and (len(cur) >= max_per_cluster or (c["start"] - cur[-1]["start"]) > gap):
            clusters.append(cur)
            cur = []
        cur.append(c)
    if cur:
        clusters.append(cur)
    return clusters


def _caption_groups(words: list[dict], size: int = 8) -> list[dict]:
    groups = []
    for i in range(0, len(words), size):
        chunk = words[i:i + size]
        groups.append({
            "start": chunk[0]["start"],
            "end": chunk[-1]["end"],
            "words": chunk,
        })
    return groups


_CSS = """
* { margin:0; padding:0; box-sizing:border-box; font-family:'Segoe UI',system-ui,sans-serif; }
body { width:1280px; height:720px; overflow:hidden; }
#stage { width:1280px; height:720px; position:relative; display:flex;
         flex-direction:column; align-items:center; }
.topbar { width:100%; padding:26px 40px 10px; text-align:center; z-index:5; }
.topbar h1 { font-size:34px; font-weight:800; }
.blob { position:absolute; border-radius:50%; filter:blur(60px); opacity:.35; z-index:0; }
.b1 { width:480px;height:480px;background:#a78bfa;top:-120px;left:-100px;animation:f1 9s ease-in-out infinite; }
.b2 { width:420px;height:420px;background:#38bdf8;bottom:-140px;right:-80px;animation:f2 8s ease-in-out infinite; }
@keyframes f1 { 0%,100%{transform:translate(0,0) scale(1);} 50%{transform:translate(70px,50px) scale(1.15);} }
@keyframes f2 { 0%,100%{transform:translate(0,0) scale(1);} 50%{transform:translate(-60px,-40px) scale(1.2);} }

.visual { flex:1; width:100%; display:flex; align-items:center; justify-content:center;
          position:relative; z-index:2; }
/* each cluster holds 1-3 illustrations that build up in a centered row */
.cluster { position:absolute; inset:0; display:flex; align-items:center; justify-content:center;
           gap:50px; opacity:0; pointer-events:none; }
.cluster.show { opacity:1; }
.cluster.out  { animation:clusterOut .5s ease forwards; }
@keyframes clusterOut { from{opacity:1;} to{opacity:0;transform:scale(.92);} }

.cue { display:flex; flex-direction:column; align-items:center; gap:16px;
       opacity:0; transform:scale(.5) translateY(30px); }
.cue.show { animation:popIn .6s cubic-bezier(.2,1.5,.4,1) forwards; }
/* svg sizes shrink as more items share the row */
.cue svg { width:340px; height:340px; transition:width .4s ease, height .4s ease; }
.cluster[data-n="2"] .cue svg { width:300px; height:300px; }
.cluster[data-n="3"] .cue svg { width:250px; height:250px; }
.cue .label { font-size:26px; font-weight:800; padding:8px 24px; border-radius:30px; }
@keyframes popIn { from{opacity:0;transform:scale(.5) translateY(30px);} to{opacity:1;transform:scale(1) translateY(0);} }

.caption { width:100%; padding:24px 40px 40px; text-align:center; z-index:5; min-height:120px; }
.cap-line { font-size:32px; font-weight:600; line-height:1.4; display:none; }
.cap-line.active { display:block; }
.cap-word { transition:color .1s, background .1s; padding:2px 4px; border-radius:6px; }
.cap-word.spoken { color:#2563eb; }
.cap-word.active { background:#fde68a; color:#1e293b; }
"""

_STYLE_BG = {
    "modern":    "body,#stage{background:#ffffff;color:#1e293b;} .cue .label{background:#fde68a;color:#92400e;} .topbar h1{color:#1e293b;}",
    "flatcolor": "body,#stage{background:linear-gradient(135deg,#1d4ed8,#3b82f6 60%,#0ea5e9);color:#fff;} .cue .label{background:rgba(255,255,255,.2);color:#fff;} .cap-word.spoken{color:#fde68a;} .topbar h1{color:#fff;}",
    "dark":      "body,#stage{background:linear-gradient(135deg,#0f172a,#1e293b);color:#fff;} .cue .label{background:#2563eb;color:#fff;} .cap-word.spoken{color:#38bdf8;} .topbar h1{color:#fff;}",
}


def render_synced_html(title: str, words: list[dict], cues: list[dict],
                       audio_dur: float, style: str = "modern") -> str:
    groups = _caption_groups(words)
    clusters = cluster_cues(cues)

    # Render clusters; each holds 1-3 cues that pop in one by one and hold.
    cluster_divs = ""
    cluster_starts = []
    for ci, cl in enumerate(clusters):
        cluster_starts.append(cl[0]["start"])
        items = "".join(
            f'<div class="cue" data-start="{c["start"]:.2f}">{c["svg"]}'
            f'<div class="label">{_e(c["label"])}</div></div>'
            for c in cl
        )
        cluster_divs += f'<div class="cluster" data-cluster="{ci}" data-n="{len(cl)}" data-start="{cl[0]["start"]:.2f}">{items}</div>'

    cap_html = ""
    for gi, g in enumerate(groups):
        spans = "".join(
            f'<span class="cap-word" data-start="{w["start"]:.2f}" data-end="{w["end"]:.2f}">{_e(w["word"])} </span>'
            for w in g["words"]
        )
        cap_html += f'<div class="cap-line" data-line="{gi}" data-start="{g["start"]:.2f}" data-end="{g["end"]:.2f}">{spans}</div>'

    starts_json = json.dumps(cluster_starts)
    bg = _STYLE_BG.get(style, _STYLE_BG["modern"])

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>{_CSS}{bg}</style></head>
<body>
<div id="stage">
  <div class="blob b1"></div><div class="blob b2"></div>
  <div class="topbar"><h1>{_e(title)}</h1></div>
  <div class="visual">{cluster_divs}</div>
  <div class="caption">{cap_html}</div>
</div>
<script>
const clusterStarts = {starts_json};
const clusters = [...document.querySelectorAll('.cluster')];
const lines = [...document.querySelectorAll('.cap-line')];
const capWords = [...document.querySelectorAll('.cap-word')];
let t0 = null, curCluster = -1;

function frame(ts) {{
  if (t0 === null) t0 = ts;
  const t = (ts - t0) / 1000;

  // which cluster is active (latest whose start has passed)
  let ci = -1;
  for (let i = 0; i < clusterStarts.length; i++) if (clusterStarts[i] <= t) ci = i;
  if (ci !== curCluster) {{
    clusters.forEach((c, i) => {{
      c.classList.toggle('show', i === ci);
      c.classList.toggle('out',  i < ci);
    }});
    curCluster = ci;
  }}
  // within the active cluster, each illustration pops in at its own time and holds
  if (ci >= 0) {{
    clusters[ci].querySelectorAll('.cue').forEach(cue => {{
      if (+cue.dataset.start <= t) cue.classList.add('show');
    }});
  }}

  // karaoke captions
  lines.forEach(l => {{
    const s = +l.dataset.start, e = +l.dataset.end;
    l.classList.toggle('active', t >= s - 0.3 && t <= e + 0.6);
  }});
  capWords.forEach(w => {{
    const s = +w.dataset.start, e = +w.dataset.end;
    w.classList.toggle('spoken', t > e);
    w.classList.toggle('active', t >= s && t <= e);
  }});

  if (t < {audio_dur + 1.0}) requestAnimationFrame(frame);
  else window.__done = true;
}}
window.__done = false;
window.addEventListener('load', () => requestAnimationFrame(frame));
</script>
</body></html>"""
