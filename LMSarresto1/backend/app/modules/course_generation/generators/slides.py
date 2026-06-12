"""Enhanced slide generation: lesson content -> rich reveal.js HTML.

Slide types: title | hook | content | warning | diagram | comparison |
             timeline | knowledge_check | summary
Every slide has Font Awesome icons, short bullets, fragments/animations.
"""
import html
from app.modules.course_generation import prompts, schemas
from app.providers.llm.base import LLMProvider


def generate_slide_deck(
    llm: LLMProvider,
    content: str,
    lesson_title: str,
    lesson_content: schemas.LessonContent,
) -> schemas.SlideDeck:
    safety = "; ".join(
        f"{s.situation} -> {s.correct_action}" for s in lesson_content.safety_scenarios
    )
    instruction = prompts.SLIDES_INSTRUCTION.format(
        lesson_title=lesson_title,
        explanation=lesson_content.simplified_explanation,
        takeaways="; ".join(lesson_content.key_takeaways),
        safety=safety or "(none)",
        examples="; ".join(lesson_content.real_world_examples) or "(none)",
        summary=lesson_content.summary,
    )
    return llm.generate_structured(
        system=prompts.GROUNDING_SYSTEM,
        instruction=instruction,
        source_content=content,
        schema=schemas.SlideDeck,
        max_tokens=3500,
    )


# ── Icon map ───────────────────────────────────────────────────
_FA = {
    "warning": "fa-triangle-exclamation",
    "shield": "fa-shield-halved",
    "hardhat": "fa-helmet-safety",
    "checklist": "fa-list-check",
    "fire": "fa-fire",
    "info": "fa-circle-info",
    "gear": "fa-gears",
    "book": "fa-book-open",
    "lightbulb": "fa-lightbulb",
    "car": "fa-car",
    "road": "fa-road",
    "person": "fa-person",
    "bike": "fa-bicycle",
    "clock": "fa-clock",
    "eye": "fa-eye",
    "brain": "fa-brain",
    "heart": "fa-heart-pulse",
    "chart": "fa-chart-line",
    "check": "fa-circle-check",
    "cross": "fa-circle-xmark",
    "star": "fa-star",
    "phone": "fa-mobile",
    "speed": "fa-gauge-high",
    "sleep": "fa-bed",
}
_DEFAULT_FA = "fa-circle-dot"


def _e(s: str) -> str:
    return html.escape(s or "")


def _fa(name: str, extra_class: str = "") -> str:
    cls = _FA.get(name.lower(), _DEFAULT_FA)
    return f'<i class="fa-solid {cls} {extra_class}"></i>'


def _bullets(items: list[str], animate: bool = True) -> str:
    if not items:
        return ""
    frag = ' class="fragment fade-up"' if animate else ""
    lis = "".join(f"<li{frag}>{_e(b)}</li>" for b in items)
    return f"<ul>{lis}</ul>"


def _render_slide(s: schemas.SlideSpec) -> str:
    icon = _fa(s.icon or s.type)

    match s.type:

        case "title":
            return f"""
<section data-background-gradient="linear-gradient(135deg,#1e3a8a 0%,#2563eb 60%,#0ea5e9 100%)"
         data-transition="zoom">
  <div style="color:#fff;text-align:center">
    <div style="font-size:3rem;margin-bottom:.5rem">{_fa(s.icon or 'book','fa-2x')}</div>
    <h1 style="font-size:2rem;margin-bottom:.8rem">{_e(s.heading)}</h1>
    {f'<p style="opacity:.8;font-size:1.1rem">{_e(s.note)}</p>' if s.note else ''}
  </div>
</section>"""

        case "hook":
            return f"""
<section data-background-color="#0f172a" data-transition="fade">
  <div style="color:#fff;text-align:center">
    <p class="fragment" style="font-size:1.6rem;font-style:italic;color:#94a3b8">"{_e(s.note)}"</p>
    <h2 style="color:#38bdf8;margin-top:1rem">{_e(s.heading)}</h2>
    {_bullets(s.bullets)}
  </div>
</section>"""

        case "warning":
            bullets_html = "".join(
                f'<li class="fragment fade-up" style="margin:.4rem 0">'
                f'{_fa("cross","" )} {_e(b)}</li>'
                for b in s.bullets
            )
            return f"""
<section data-background-color="#7f1d1d" data-transition="fade">
  <div style="color:#fff;text-align:center">
    <div style="font-size:2.5rem;margin-bottom:.5rem;animation:pulse 1.5s infinite">
      {_fa('warning','fa-2x')} </div>
    <h2 style="color:#fca5a5">{_e(s.heading) or 'Safety Warning'}</h2>
    <ul style="list-style:none;text-align:left;display:inline-block">{bullets_html}</ul>
    {f'<div class="fragment" style="margin-top:1rem;padding:.8rem;background:rgba(255,255,255,.15);border-radius:8px;font-size:.9rem">{_e(s.note)}</div>' if s.note else ''}
  </div>
</section>"""

        case "diagram":
            return f"""
<section data-transition="slide">
  <h2>{icon} {_e(s.heading)}</h2>
  <div style="border:2px dashed #2563eb;border-radius:12px;padding:1.5rem;
              margin:1rem auto;max-width:75%;background:#eff6ff;font-style:italic;
              font-size:1rem;color:#1e40af">
    {_fa('chart')} {_e(s.diagram)}
  </div>
  {_bullets(s.bullets)}
</section>"""

        case "comparison":
            mid = len(s.bullets) // 2
            left = s.bullets[:mid]
            right = s.bullets[mid:]
            left_li = "".join(f"<li class='fragment'>{_fa('cross')} {_e(b)}</li>" for b in left)
            right_li = "".join(f"<li class='fragment'>{_fa('check')} {_e(b)}</li>" for b in right)
            return f"""
<section data-transition="slide">
  <h2>{icon} {_e(s.heading)}</h2>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin-top:1rem">
    <div style="background:#fef2f2;padding:1rem;border-radius:8px;border-left:4px solid #ef4444">
      <h4 style="color:#dc2626">{_fa('cross')} Don't</h4>
      <ul style="font-size:.85rem">{left_li}</ul>
    </div>
    <div style="background:#f0fdf4;padding:1rem;border-radius:8px;border-left:4px solid #22c55e">
      <h4 style="color:#16a34a">{_fa('check')} Do</h4>
      <ul style="font-size:.85rem">{right_li}</ul>
    </div>
  </div>
</section>"""

        case "timeline":
            steps = "".join(
                f'''<div class="fragment fade-up" style="display:flex;align-items:center;
                    gap:.8rem;margin:.5rem 0;background:#f8fafc;padding:.6rem 1rem;
                    border-radius:8px;border-left:4px solid #2563eb">
                  <span style="background:#2563eb;color:#fff;border-radius:50%;
                        width:2rem;height:2rem;display:flex;align-items:center;
                        justify-content:center;flex-shrink:0;font-weight:bold">{i+1}</span>
                  <span>{_e(b)}</span></div>'''
                for i, b in enumerate(s.bullets)
            )
            return f"""
<section data-transition="slide">
  <h2>{icon} {_e(s.heading)}</h2>
  <div style="max-width:80%;margin:0 auto">{steps}</div>
</section>"""

        case "knowledge_check":
            options = "".join(
                f'<div class="fragment fade-up" style="background:#f1f5f9;padding:.6rem 1rem;'
                f'border-radius:8px;margin:.3rem 0;cursor:pointer;font-size:.9rem">'
                f'{chr(65+i)}. {_e(b)}</div>'
                for i, b in enumerate(s.bullets)
            )
            return f"""
<section data-background-color="#0f4c75" data-transition="convex">
  <div style="color:#fff">
    <h3>{_fa('brain')} Quick Check</h3>
    <p style="font-size:1.1rem;margin:1rem 0;background:rgba(255,255,255,.1);
              padding:1rem;border-radius:8px">{_e(s.heading)}</p>
    <div style="text-align:left">{options}</div>
    {f'<p class="fragment" style="margin-top:1rem;background:#22c55e;padding:.6rem 1rem;border-radius:8px;font-size:.9rem">{_fa("check")} {_e(s.note)}</p>' if s.note else ''}
  </div>
</section>"""

        case "summary":
            items = "".join(
                f'<div class="fragment fade-up" style="display:flex;align-items:center;'
                f'gap:.6rem;margin:.4rem 0">'
                f'{_fa("check","" )} <span>{_e(b)}</span></div>'
                for b in s.bullets
            )
            return f"""
<section data-background-gradient="linear-gradient(135deg,#064e3b,#065f46)"
         data-transition="zoom">
  <div style="color:#fff;text-align:center">
    <div style="font-size:2rem;margin-bottom:.5rem">{_fa('star','fa-2x')}</div>
    <h2>{_e(s.heading) or 'Key Takeaways'}</h2>
    <div style="text-align:left;display:inline-block;margin-top:.8rem">{items}</div>
  </div>
</section>"""

        case _:  # content (default)
            return f"""
<section data-transition="slide">
  <h2>{icon} {_e(s.heading)}</h2>
  {_bullets(s.bullets)}
  {f'<p class="fragment" style="margin-top:1rem;font-size:.85rem;color:#64748b;border-top:1px solid #e2e8f0;padding-top:.6rem">{_e(s.note)}</p>' if s.note else ''}
</section>"""


_CSS = """
@import url('https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css');
:root { --r-background-color:#fff; --r-main-font-size:24px; }
.reveal h1,.reveal h2 { font-family:'Segoe UI',sans-serif; }
.reveal section[data-background-gradient] h1,
.reveal section[data-background-gradient] h2,
.reveal section[data-background-gradient] p,
.reveal section[data-background-color="#7f1d1d"] h2,
.reveal section[data-background-color="#0f172a"] h2,
.reveal section[data-background-color="#0f4c75"] h3 { color:#fff; }
.reveal ul { display:inline-block; text-align:left; }
.reveal li { margin:.3rem 0; }
@keyframes pulse {
  0%,100% { transform:scale(1); }
  50%      { transform:scale(1.15); }
}
"""


def render_reveal_html(lesson_title: str, slides: list[schemas.SlideSpec]) -> str:
    sections = "\n".join(_render_slide(s) for s in slides)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>{_e(lesson_title)}</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/reveal.js@5/dist/reveal.css">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/reveal.js@5/dist/theme/white.css">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
<style>{_CSS}</style>
</head>
<body>
<div class="reveal"><div class="slides">
{sections}
</div></div>
<script src="https://cdn.jsdelivr.net/npm/reveal.js@5/dist/reveal.js"></script>
<script src="https://cdn.jsdelivr.net/npm/reveal.js@5/plugin/notes/notes.js"></script>
<script src="https://cdn.jsdelivr.net/npm/reveal.js@5/plugin/zoom/zoom.js"></script>
<script>
Reveal.initialize({{
  hash: true,
  transition: 'slide',
  transitionSpeed: 'default',
  backgroundTransition: 'fade',
  autoAnimateEasing: 'ease-out',
  autoAnimateDuration: 0.8,
  plugins: [ RevealNotes, RevealZoom ],
  keyboard: {{ 39: 'next', 37: 'prev' }}
}});
</script>
</body>
</html>"""
