"""
Course script generator — transforms document content into structured
educational scripts ready for PPT / audio / video generation pipelines.

Three-step generation (all via Claude)
---------------------------------------
1. ANALYSE   — read document chunks, identify topics + key concepts
2. OUTLINE   — design module/lesson structure with hard duration constraints
3. SCRIPT    — write each lesson: narration, bullets, visuals, objectives

All user-selected settings (language, duration, difficulty, topic focus,
learning objectives, depth, tone) are injected as EXPLICIT named constraints
into every Claude prompt, not buried in a generic "additional instructions" block.
"""

from __future__ import annotations

import json
import os
import re
import logging

logger = logging.getLogger("arresto.course_generator")

from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Callable

if TYPE_CHECKING:
    from modules.content_ingestion.embedder import Embedder
    from modules.content_ingestion.vector_store import VectorStore


# ── Output data models ─────────────────────────────────────────────────────────

@dataclass
class SlideContent:
    title:         str
    bullets:       list[str]
    speaker_notes: str = ""


@dataclass
class LessonScript:
    lesson_number:           int
    lesson_title:            str
    duration_minutes:        int
    learning_objectives:     list[str]
    narration_script:        str
    slide_content:           SlideContent
    visual_description:      str
    key_terms:               list[str]
    summary:                 str       = ""
    simplified_explanation:  str       = ""
    key_takeaways:           list[str] = field(default_factory=list)
    real_world_examples:     list[dict] = field(default_factory=list)
    safety_scenarios:        list[dict] = field(default_factory=list)


@dataclass
class ModuleScript:
    module_number:      int
    module_title:       str
    module_description: str
    lessons:            list[LessonScript] = field(default_factory=list)


@dataclass
class CourseScript:
    course_title:                 str
    course_description:           str
    target_audience:              str
    estimated_total_duration_min: int
    source_documents:             list[str]
    modules:                      list[ModuleScript] = field(default_factory=list)
    items:                        list[dict]         = field(default_factory=list)

    def to_dict(self) -> dict:
        def lesson_d(l: LessonScript) -> dict:
            return {
                "lesson_number":          l.lesson_number,
                "lesson_title":           l.lesson_title,
                "duration_minutes":       l.duration_minutes,
                "learning_objectives":    l.learning_objectives,
                "narration_script":       l.narration_script,
                "slide_content": {
                    "title":         l.slide_content.title,
                    "bullets":       l.slide_content.bullets,
                    "speaker_notes": l.slide_content.speaker_notes,
                },
                "visual_description":     l.visual_description,
                "key_terms":              l.key_terms,
                "summary":                l.summary,
                "simplified_explanation": l.simplified_explanation,
                "key_takeaways":          l.key_takeaways,
                "real_world_examples":    l.real_world_examples,
                "safety_scenarios":       l.safety_scenarios,
            }

        def module_d(m: ModuleScript) -> dict:
            return {
                "module_number":      m.module_number,
                "module_title":       m.module_title,
                "module_description": m.module_description,
                "lessons":            [lesson_d(l) for l in m.lessons],
            }

        seen: set[str] = set()
        top_objectives: list[str] = []
        for m in self.modules:
            for l in m.lessons:
                for obj in l.learning_objectives:
                    if obj not in seen:
                        top_objectives.append(obj)
                        seen.add(obj)

        result = {
            "course_title":                 self.course_title,
            "description":                  self.course_description,
            "course_description":           self.course_description,
            "learning_objectives":          top_objectives[:6],
            "target_audience":              self.target_audience,
            "estimated_total_duration_min": self.estimated_total_duration_min,
            "source_documents":             self.source_documents,
            "modules":                      [module_d(m) for m in self.modules],
        }
        if self.items:
            result["items"] = self.items
        return result

    def save(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2, ensure_ascii=False)
        logger.info("Course script saved -> %s", path)


# ── Generator ──────────────────────────────────────────────────────────────────

class CourseGenerator:
    _MODEL = "claude-sonnet-4-6"

    def __init__(
        self,
        vector_store: "VectorStore",
        api_key:      str | None = None,
        model:        str | None = None,
        embedder:     "Embedder | None" = None,
    ) -> None:
        self._store    = vector_store
        self._model    = model or self._MODEL
        self._embedder = embedder
        self._inline_text: str | None = None

        key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        if not key:
            raise RuntimeError(
                "CourseGenerator requires an Anthropic API key. "
                "Set ANTHROPIC_API_KEY or pass api_key=."
            )
        import anthropic
        self._client = anthropic.Anthropic(api_key=key, timeout=120.0)

    # ── Duration helpers ────────────────────────────────────────────────────────

    @staticmethod
    def _duration_limits(duration_range: str) -> tuple[int, int, int, int, int]:
        """
        Returns (max_total_min, max_modules, max_lessons_per_module,
                 min_lesson_min, max_lesson_min) for the selected duration band.
        These are HARD limits — enforced programmatically after outline generation.
        """
        d = duration_range.lower()
        if "15" in d or "20" in d:
            # 15-20 min total → 1 module, 2 lessons, 5-8 min/lesson
            return 20, 1, 2, 5, 8
        elif "30" in d or "45" in d:
            # 30-45 min total → 2 modules, 3 lessons each, 5-8 min/lesson
            return 45, 2, 3, 5, 8
        elif "3" in d and ("hour" in d or "+" in d):
            # 3+ hours → 5 modules, 6 lessons each, 12-18 min/lesson
            return 240, 5, 6, 12, 18
        elif "2" in d and "hour" in d:
            # 2-3 hours → 4 modules, 5 lessons each, 10-15 min/lesson
            return 180, 4, 5, 10, 15
        else:
            # 60-90 min (default) → 3 modules, 4 lessons each, 7-10 min/lesson
            return 90, 3, 4, 7, 10

    @staticmethod
    def _duration_prompt_rules(duration_range: str) -> str:
        """Returns the duration constraints as a formatted string for Claude prompts."""
        d = duration_range.lower()
        if "15" in d or "20" in d:
            return (
                "TOTAL DURATION: 15 to 20 minutes maximum\n"
                "  - 1 module only\n"
                "  - 2 lessons maximum\n"
                "  - 5 to 8 minutes per lesson (duration_minutes between 5 and 8)"
            )
        elif "30" in d or "45" in d:
            return (
                "TOTAL DURATION: 30 to 45 minutes maximum\n"
                "  - 1 to 2 modules\n"
                "  - 2 to 3 lessons per module\n"
                "  - 5 to 8 minutes per lesson (duration_minutes between 5 and 8)"
            )
        elif "3" in d and ("hour" in d or "+" in d):
            return (
                "TOTAL DURATION: 3 or more hours\n"
                "  - 4 to 5 modules\n"
                "  - 4 to 6 lessons per module\n"
                "  - 12 to 18 minutes per lesson (duration_minutes between 12 and 18)"
            )
        elif "2" in d and "hour" in d:
            return (
                "TOTAL DURATION: 2 to 3 hours\n"
                "  - 3 to 4 modules\n"
                "  - 4 to 5 lessons per module\n"
                "  - 10 to 15 minutes per lesson (duration_minutes between 10 and 15)"
            )
        else:
            return (
                "TOTAL DURATION: 60 to 90 minutes\n"
                "  - 2 to 3 modules\n"
                "  - 3 to 4 lessons per module\n"
                "  - 7 to 10 minutes per lesson (duration_minutes between 7 and 10)"
            )

    @staticmethod
    def _parse_structure_overrides(user_instructions: str | None) -> tuple[int | None, int | None]:
        """
        Extract explicit module / lesson counts from free-form user instructions.
        Returns (module_count, lessons_per_module) — either may be None if not found.
        Examples matched: "5 modules", "3 lessons per module", "generate 4 modules with 5 lessons"
        """
        if not user_instructions:
            return None, None
        mod_m = re.search(r'\b(\d+)\s+module', user_instructions, re.IGNORECASE)
        les_m = re.search(r'\b(\d+)\s+lesson', user_instructions, re.IGNORECASE)
        mod_count = int(mod_m.group(1)) if mod_m else None
        les_count = int(les_m.group(1)) if les_m else None
        return mod_count, les_count

    def _enforce_duration(
        self,
        outline: dict,
        duration_range: str,
        user_instructions: str | None = None,
    ) -> dict:
        """
        Clamps the outline to the selected duration band.

        If the admin explicitly specified a module or lesson count in
        user_instructions, those override the duration-band defaults —
        the admin's structural intent takes priority. Per-lesson duration
        limits are always enforced to keep individual lessons sane.
        """
        max_total, max_mods, max_les, min_les_min, max_les_min = self._duration_limits(duration_range)

        # Admin-specified structure overrides duration-band caps
        user_mod_count, user_les_count = self._parse_structure_overrides(user_instructions)
        if user_mod_count is not None:
            logger.info("User specified %d modules — overriding duration-band cap of %d.", user_mod_count, max_mods)
            max_mods = user_mod_count
            max_total = max_total * max_mods // max(1, self._duration_limits(duration_range)[1])
        if user_les_count is not None:
            logger.info("User specified %d lessons/module — overriding duration-band cap of %d.", user_les_count, max_les)
            max_les = user_les_count

        outline["modules"] = outline["modules"][:max_mods]

        for mod in outline["modules"]:
            mod["lessons"] = mod["lessons"][:max_les]
            for les in mod["lessons"]:
                raw = int(les.get("duration_minutes", max_les_min))
                les["duration_minutes"] = max(min_les_min, min(raw, max_les_min))

        total = sum(
            les["duration_minutes"]
            for mod in outline["modules"]
            for les in mod["lessons"]
        )
        if total > max_total:
            scale = max_total / total
            for mod in outline["modules"]:
                for les in mod["lessons"]:
                    les["duration_minutes"] = max(min_les_min, int(les["duration_minutes"] * scale))

        final_total = sum(les["duration_minutes"] for mod in outline["modules"] for les in mod["lessons"])
        final_lessons = sum(len(mod["lessons"]) for mod in outline["modules"])
        logger.info(
            "Duration enforced for '%s': %d modules, %d lessons, %d min total",
            duration_range, len(outline["modules"]), final_lessons, final_total,
        )
        return outline

    # ── Instructions parser ─────────────────────────────────────────────────────

    @staticmethod
    def _parse_instructions(instructions: str | None) -> dict:
        """
        Extracts structured fields from the instructions string built by the
        Flutter wizard. The wizard concatenates fields as:
          'Topic focus: X. Course description: Y. Difficulty level: Z.
           Learning objectives: W. Depth: V. Tone: U.'

        Returns a dict with keys: topic, description, difficulty,
        objectives, depth, tone. Any field absent in the string is omitted.
        """
        if not instructions:
            return {}

        result: dict[str, str] = {}

        # Use lookahead for known field labels as stop markers so a multi-sentence
        # description (or one that ends with a period) doesn't bleed into the next field.
        _NEXT = r"(?=\s*(?:Topic focus:|Course description:|Difficulty level:|Learning objectives:|Depth:|Tone:)|$)"

        patterns = {
            "topic":       rf"Topic focus:\s*(.*?){_NEXT}",
            "description": rf"Course description:\s*(.*?){_NEXT}",
            "difficulty":  r"Difficulty level:\s*(\w[\w\s]*?)(?=[.\s]*(?:Learning objectives:|Depth:|Tone:|Topic focus:|Course description:|$))",
            "objectives":  rf"Learning objectives:\s*(.*?){_NEXT}",
            "depth":       r"Depth:\s*(\w[\w\s]*?)(?:\.|$)",
            "tone":        r"Tone:\s*(\w[\w\s]*?)(?:\.|$)",
        }

        for key, pattern in patterns.items():
            m = re.search(pattern, instructions, re.IGNORECASE | re.DOTALL)
            if m:
                val = m.group(1).strip().rstrip(".")
                if val:
                    result[key] = val

        return result

    # ── Sanitization ────────────────────────────────────────────────────────────

    _CTRL_CHAR_RE     = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
    _MAX_INSTRUCTIONS = 5_000

    @classmethod
    def _sanitize_instructions(cls, text: str | None) -> str | None:
        if not text:
            return text
        text = cls._CTRL_CHAR_RE.sub("", text)
        if len(text) > cls._MAX_INSTRUCTIONS:
            logger.warning("instructions truncated from %d to %d chars.", len(text), cls._MAX_INSTRUCTIONS)
            text = text[: cls._MAX_INSTRUCTIONS]
        return text.strip() or None

    # ── Claude call helpers ─────────────────────────────────────────────────────

    _MAX_INPUT_CHARS = 600_000

    def _call(self, prompt: str, system: str = "", max_tokens: int = 4096) -> str:
        system_text = system or (
            "You are an expert instructional designer who transforms raw "
            "document content into engaging, clear educational material. "
            "You always return valid JSON when asked. "
            "You follow all constraints EXACTLY — language, duration, difficulty, tone."
        )
        total_chars = len(prompt) + len(system_text)
        if total_chars > self._MAX_INPUT_CHARS:
            raise ValueError(
                f"Prompt too large: {total_chars:,} chars. Reduce source document size."
            )
        resp = self._client.messages.create(
            model=self._model,
            max_tokens=max_tokens,
            system=system_text,
            messages=[{"role": "user", "content": prompt}],
        )
        return resp.content[0].text

    def _parse_json(self, text: str) -> dict:
        """
        Extract and parse JSON from a response that may have markdown fences.
        Falls back to json-repair for common Claude quirks (trailing commas,
        truncated responses, unescaped newlines in strings).
        """
        text = text.strip()

        # 1. Direct parse (fastest path — no fences, clean JSON)
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        # 2. Strip markdown fences then try again
        candidate = text
        if "```" in text:
            for fence in ("```json", "```"):
                if fence in text:
                    after = text[text.index(fence) + len(fence):]
                    end_fence = after.find("```")
                    candidate = after[:end_fence].strip() if end_fence != -1 else after.strip()
                    try:
                        return json.loads(candidate)
                    except json.JSONDecodeError:
                        break  # try repair on this candidate below

        # 3. Isolate the outermost {...} block
        start = candidate.find("{")
        end   = candidate.rfind("}") + 1
        if start != -1 and end > start:
            candidate = candidate[start:end]

        # 4. json-repair — handles trailing commas, truncated JSON, bad escapes
        try:
            from json_repair import repair_json
            repaired = repair_json(candidate, return_objects=True)
            if isinstance(repaired, dict):
                return repaired
        except Exception:
            pass

        # 5. Last resort: strict parse with descriptive error
        try:
            return json.loads(candidate)
        except json.JSONDecodeError as exc:
            raise ValueError(
                f"Could not parse JSON from model response. "
                f"Error: {exc}. Response (first 300 chars): {text[:300]!r}"
            ) from exc

    # ── Relevant chunk retrieval ────────────────────────────────────────────────

    def _get_lesson_context(
        self,
        topic_focus:        str,
        source_file:        str,
        fallback_content:   str,
        n_chunks:           int  = 8,
        use_knowledge_base: bool = False,
    ) -> str:
        if self._inline_text is not None:
            return self._inline_text[:5000]
        if self._embedder is None:
            return fallback_content[:5000]
        q_vec = self._embedder.embed_query(topic_focus)
        filter_file = None if use_knowledge_base else source_file
        hits = self._store.query(q_vec, n_results=n_chunks, source_file=filter_file)
        if not hits:
            return fallback_content[:5000]
        return "\n\n".join(
            f"[{h['metadata'].get('section_heading', '')}]\n{h['text']}"
            for h in hits
        )

    # ── Public API ──────────────────────────────────────────────────────────────

    @staticmethod
    def _user_req_block(user_instructions: str | None) -> str:
        """Format admin's free-form instructions as a strict constraint block."""
        if not user_instructions or not user_instructions.strip():
            return ""
        return (
            "\nCRITICAL USER REQUIREMENTS — FOLLOW EXACTLY:\n"
            "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"{user_instructions.strip()}\n"
            "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            "These are NON-NEGOTIABLE requirements from the course designer.\n"
            "They override all defaults above. Implement them literally.\n"
        )

    def generate(
        self,
        source_file:        str,
        course_title:       str | None = None,
        target_audience:    str = "learners",
        progress_callback:  "Callable[[int, int], None] | None" = None,
        instructions:       str | None = None,
        user_instructions:  str | None = None,
        use_knowledge_base: bool = False,
        language:           str = "English",
        duration_range:     str = "60-90 minutes",
    ) -> CourseScript:
        """
        Generate a complete course from a document in the vector store.

        Parameters
        ----------
        source_file      : filename as stored (e.g. "Safety Manual.pdf")
        course_title     : override title; Claude auto-generates if None
        target_audience  : who the course is for
        instructions     : composite string from the Flutter wizard containing
                           topic focus, description, difficulty level, learning
                           objectives, depth, and tone
        use_knowledge_base: search across all docs (not just source_file)
        language         : ALL content output language (e.g. "Hindi", "Spanish")
        duration_range   : "30-45 minutes" | "60-90 minutes" | "2-3 hours" | "3+ hours"
        """
        instructions = self._sanitize_instructions(instructions)
        parsed = self._parse_instructions(instructions)

        logger.info(
            "generate() called: source='%s', language='%s', duration='%s', "
            "difficulty='%s', topic='%s'",
            source_file, language, duration_range,
            parsed.get("difficulty", "not set"), parsed.get("topic", "not set"),
        )

        chunks = self._store.get_all_by_source(source_file)
        if not chunks:
            raise ValueError(
                f"No chunks found for '{source_file}'. "
                "Run the ingestion pipeline on this file first."
            )

        full_content = "\n\n".join(
            f"[{c['metadata'].get('section_heading', '')}]\n{c['text']}"
            for c in chunks
        )
        logger.info("%d chunks loaded (%d chars).", len(chunks), len(full_content))

        user_req = self._user_req_block(user_instructions)

        # Step 1 — analyse
        logger.info("Step 1/3: Analysing content ...")
        analysis = self._analyse(full_content, source_file, target_audience, parsed, language, user_req)

        # Step 2 — outline (with duration constraints baked into the prompt)
        logger.info("Step 2/3: Building course outline ...")
        title = course_title or analysis.get("suggested_title", source_file)
        outline = self._outline(analysis, title, target_audience, parsed, language, duration_range, user_req, user_instructions)

        # Clamp outline — user_instructions can override module/lesson counts
        outline = self._enforce_duration(outline, duration_range, user_instructions)

        total_lessons = sum(len(m["lessons"]) for m in outline["modules"])
        logger.info("Step 3/3: Scripting %d lessons ...", total_lessons)

        # Step 3 — script each lesson
        modules = self._script_all(
            outline, full_content, target_audience, source_file,
            progress_callback, parsed, use_knowledge_base, language, user_req,
        )

        total_mins = sum(l.duration_minutes for m in modules for l in m.lessons)
        return CourseScript(
            course_title=outline["course_title"],
            course_description=outline["course_description"],
            target_audience=target_audience,
            estimated_total_duration_min=total_mins,
            source_documents=[source_file],
            modules=modules,
        )

    # ── Step 1: Analyse ─────────────────────────────────────────────────────────

    def _analyse(
        self,
        content:    str,
        source_file: str,
        audience:   str,
        parsed:     dict,
        language:   str,
        user_req:   str = "",
    ) -> dict:
        topic_line       = f"TOPIC FOCUS: {parsed['topic']}" if parsed.get("topic") else ""
        description_line = f"COURSE DESCRIPTION: {parsed['description']}" if parsed.get("description") else ""
        difficulty_line  = f"DIFFICULTY LEVEL: {parsed['difficulty']}" if parsed.get("difficulty") else ""

        prompt = f"""Analyse the following document content extracted from "{source_file}".

═══ FIXED CONSTRAINTS ═══════════════════════════════════════════
OUTPUT LANGUAGE: {language}
  → Write ALL fields (titles, summaries, topics, concepts) in {language}.
TARGET AUDIENCE: {audience}
{topic_line}
{description_line}
{difficulty_line}
{user_req}═════════════════════════════════════════════════════════════════

DOCUMENT CONTENT:
{content[:6000]}

Return a JSON object — write ALL text values in {language}:
{{
  "suggested_title": "short course title based on content and topic focus above",
  "document_type": "safety manual / technical guide / process document / etc.",
  "main_topics": ["topic 1", "topic 2", "..."],
  "key_concepts": ["concept 1", "concept 2", "..."],
  "difficulty_level": "{parsed.get('difficulty', 'beginner / intermediate / advanced')}",
  "content_summary": "2-3 sentence summary of what this document covers"
}}

Return ONLY the JSON, no other text.
"""
        raw = self._call(prompt)
        return self._parse_json(raw)

    # ── Step 2: Outline ─────────────────────────────────────────────────────────

    def _outline(
        self,
        analysis:       dict,
        course_title:   str,
        audience:       str,
        parsed:            dict,
        language:          str  = "English",
        duration_range:    str  = "60-90 minutes",
        user_req:          str  = "",
        user_instructions: str | None = None,
    ) -> dict:
        _, _, _, min_les_min, max_les_min = self._duration_limits(duration_range)
        example_dur = (min_les_min + max_les_min) // 2
        duration_rules = self._duration_prompt_rules(duration_range)

        # If admin explicitly specified structure, add it to the prompt so Claude generates the right count
        user_mod_count, user_les_count = self._parse_structure_overrides(user_instructions)
        if user_mod_count is not None or user_les_count is not None:
            overrides = []
            if user_mod_count is not None:
                overrides.append(f"  - EXACTLY {user_mod_count} modules (admin requirement — do not reduce)")
            if user_les_count is not None:
                overrides.append(f"  - EXACTLY {user_les_count} lessons per module (admin requirement — do not reduce)")
            duration_rules += "\nADMIN STRUCTURE OVERRIDE (takes priority over duration band):\n" + "\n".join(overrides)

        objectives_line = f"LEARNING OBJECTIVES TO COVER: {parsed['objectives']}" if parsed.get("objectives") else ""
        difficulty_line = f"DIFFICULTY LEVEL: {parsed.get('difficulty', analysis.get('difficulty_level', 'intermediate'))}"
        depth_line      = f"DEPTH: {parsed['depth']}" if parsed.get("depth") else ""
        tone_line       = f"TONE: {parsed['tone']}" if parsed.get("tone") else ""

        prompt = f"""Design a structured course outline based on the content analysis below.

═══ FIXED CONSTRAINTS — FOLLOW EXACTLY ═════════════════════════
OUTPUT LANGUAGE: {language}
  → Write ALL text fields (titles, descriptions) in {language}.

{duration_rules}
  → These are HARD limits. Do NOT exceed them.
  → The sum of all duration_minutes MUST NOT exceed the total duration above.

{difficulty_line}
{objectives_line}
{depth_line}
{tone_line}
{user_req}═════════════════════════════════════════════════════════════════

CONTENT ANALYSIS:
{json.dumps(analysis, indent=2, ensure_ascii=False)}

COURSE TITLE: {course_title}
TARGET AUDIENCE: {audience}

Design the outline. Progress logically: fundamentals → application → advanced.
Each lesson must build on the previous — no repeated content.

Return a JSON object — ALL text in {language}:
{{
  "course_title": "{course_title}",
  "course_description": "2-sentence course description in {language}",
  "modules": [
    {{
      "module_number": 1,
      "module_title": "module title in {language}",
      "module_description": "one sentence in {language}",
      "lessons": [
        {{
          "lesson_number": 1,
          "lesson_title": "lesson title in {language}",
          "topic_focus": "specific topic this lesson covers",
          "duration_minutes": {example_dur}
        }}
      ]
    }}
  ]
}}

Return ONLY the JSON.
"""
        raw = self._call(prompt)
        return self._parse_json(raw)

    # ── Step 3: Script each lesson ──────────────────────────────────────────────

    def _script_all(
        self,
        outline:            dict,
        content:            str,
        audience:           str,
        source_file:        str,
        progress_callback:  "Callable[[int, int], None] | None" = None,
        parsed:             dict | None = None,
        use_knowledge_base: bool = False,
        language:           str = "English",
        user_req:           str = "",
    ) -> list[ModuleScript]:
        parsed = parsed or {}
        total = sum(len(m["lessons"]) for m in outline["modules"])
        done  = 0
        modules_out: list[ModuleScript] = []

        for mod in outline["modules"]:
            lessons_out: list[LessonScript] = []
            for les in mod["lessons"]:
                last_exc: Exception | None = None
                for attempt in range(2):
                    try:
                        ls = self._script_lesson(
                            les, mod, content, audience, source_file,
                            parsed, use_knowledge_base, language, user_req,
                        )
                        last_exc = None
                        break
                    except Exception as exc:
                        last_exc = exc
                        logger.warning(
                            "  [retry %d/2] lesson '%s' failed: %s",
                            attempt + 1, les["lesson_title"], exc,
                        )
                if last_exc is not None:
                    raise last_exc
                lessons_out.append(ls)
                done += 1
                if progress_callback:
                    progress_callback(done, total)
                logger.info("  [ok] (%d/%d) %s > %s", done, total, mod["module_title"], les["lesson_title"])

            modules_out.append(ModuleScript(
                module_number=mod["module_number"],
                module_title=mod["module_title"],
                module_description=mod["module_description"],
                lessons=lessons_out,
            ))

        return modules_out

    def _script_lesson(
        self,
        lesson:             dict,
        module:             dict,
        content:            str,
        audience:           str,
        source_file:        str,
        parsed:             dict | None = None,
        use_knowledge_base: bool = False,
        language:           str = "English",
        user_req:           str = "",
    ) -> LessonScript:
        parsed = parsed or {}
        context = self._get_lesson_context(
            lesson["topic_focus"], source_file, content,
            use_knowledge_base=use_knowledge_base,
        )

        difficulty_line  = f"DIFFICULTY: {parsed['difficulty']}" if parsed.get("difficulty") else ""
        objectives_line  = f"LEARNING OBJECTIVES TO HIT: {parsed['objectives']}" if parsed.get("objectives") else ""
        depth_line       = f"DEPTH: {parsed['depth']}" if parsed.get("depth") else ""
        tone_line        = f"TONE: {parsed['tone']} — maintain this tone throughout the narration." if parsed.get("tone") else ""
        target_words     = lesson["duration_minutes"] * 120

        prompt = f"""Script ONE lesson for an educational course.

═══ FIXED CONSTRAINTS — FOLLOW EXACTLY ═════════════════════════
OUTPUT LANGUAGE: {language}
  → Write ALL content (narration, bullets, objectives, terms,
    examples, takeaways) in {language}. NO English unless language IS English.

{difficulty_line}
{objectives_line}
{depth_line}
{tone_line}
{user_req}═════════════════════════════════════════════════════════════════

MODULE:      {module['module_title']}
LESSON:      {lesson['lesson_title']}
TOPIC FOCUS: {lesson['topic_focus']}
DURATION:    {lesson['duration_minutes']} minutes
AUDIENCE:    {audience}

SOURCE CONTENT (use as your knowledge base):
{context}

WRITING RULES:
1. narration_script — Write as a teacher SPEAKING to the class in {language}.
   Natural, engaging, first-person plural ("Let's explore...", "Think of it...").
   Do NOT just read the document — explain, give examples, make it memorable.
   Target: ~{target_words} words (matches {lesson['duration_minutes']} min audio at 120 wpm).
2. slide_bullets — 3-5 concise bullet points. Short phrases, not full sentences.
3. speaker_notes — 1-2 sentences the presenter says while showing the slide.
4. visual_description — What appears in the video scene?
5. learning_objectives — 2-3 "By the end of this lesson, learners will be able to..." statements.
6. key_terms — 3-5 important vocabulary words from this lesson.
7. summary — 1-2 sentence overview.
8. simplified_explanation — Core concept in plain language (2-3 sentences).
9. key_takeaways — 3-4 actionable points the learner should remember.
10. real_world_examples — 2-3 examples each with situation and correct_action.
11. safety_scenarios — 2-3 safety-relevant scenarios (empty list [] if not applicable).

Return a JSON object — ALL text in {language}:
{{
  "learning_objectives": ["...", "..."],
  "narration_script": "Full spoken text in {language}...",
  "slide_content": {{
    "title": "{lesson['lesson_title']}",
    "bullets": ["point 1", "point 2", "point 3"],
    "speaker_notes": "..."
  }},
  "visual_description": "...",
  "key_terms": ["term1", "term2"],
  "summary": "1-2 sentence summary in {language}.",
  "simplified_explanation": "Plain-language explanation in {language}.",
  "key_takeaways": ["takeaway 1", "takeaway 2", "takeaway 3"],
  "real_world_examples": [
    {{"situation": "...", "correct_action": "..."}}
  ],
  "safety_scenarios": [
    {{"situation": "...", "correct_action": "..."}}
  ]
}}

Return ONLY the JSON.
"""
        raw  = self._call(prompt, max_tokens=16000)
        data = self._parse_json(raw)

        slide = SlideContent(
            title=data.get("slide_content", {}).get("title", lesson["lesson_title"]),
            bullets=data.get("slide_content", {}).get("bullets", []),
            speaker_notes=data.get("slide_content", {}).get("speaker_notes", ""),
        )
        return LessonScript(
            lesson_number=lesson["lesson_number"],
            lesson_title=lesson["lesson_title"],
            duration_minutes=lesson["duration_minutes"],
            learning_objectives=data.get("learning_objectives", []),
            narration_script=data.get("narration_script", ""),
            slide_content=slide,
            visual_description=data.get("visual_description", ""),
            key_terms=data.get("key_terms", []),
            summary=data.get("summary", ""),
            simplified_explanation=data.get("simplified_explanation", ""),
            key_takeaways=data.get("key_takeaways", []),
            real_world_examples=data.get("real_world_examples", []),
            safety_scenarios=data.get("safety_scenarios", []),
        )

    # ── Micro-course (single-pass custom blueprint) ─────────────────────────────

    def generate_micro_course(
        self,
        source_file:     str,
        instructions:    str,
        course_title:    str | None = None,
        target_audience: str = "learners",
        language:        str = "English",
    ) -> CourseScript:
        """
        Single-pass generation that treats `instructions` as an exact course blueprint.
        Use when instructions specify a precise structure: exact slide count,
        interleaved quizzes, or specific language requirements.
        """
        instructions = self._sanitize_instructions(instructions)
        logger.info("[custom] Fetching chunks for '%s' ...", source_file)
        chunks = self._store.get_all_by_source(source_file)
        if not chunks:
            raise ValueError(f"No chunks found for '{source_file}'.")

        full_content = "\n\n".join(
            f"[{c['metadata'].get('section_heading', '')}]\n{c['text']}"
            for c in chunks
        )
        logger.info("[custom] %d chunks loaded. Generating from blueprint ...", len(chunks))

        prompt = f"""You are an expert instructional designer.
Generate a complete educational course by following the COURSE BLUEPRINT below EXACTLY.

═══ FIXED CONSTRAINTS ═══════════════════════════════════════════
OUTPUT LANGUAGE: {language}
  → Write ALL text fields in {language}. NO exceptions.
TARGET AUDIENCE: {target_audience}
═════════════════════════════════════════════════════════════════

COURSE BLUEPRINT:
{instructions}

SOURCE DOCUMENT (use as your factual knowledge base):
{full_content[:9000]}

Return the complete course as a single JSON object:
{{
  "course_title": "...",
  "course_description": "...",
  "estimated_total_duration_min": <integer>,
  "items": [
    {{
      "type": "slide",
      "slide_number": 1,
      "title": "...",
      "narration": "full spoken narration text",
      "bullets": ["bullet 1", "bullet 2", "bullet 3"],
      "takeaway": "one-line takeaway sentence"
    }},
    {{
      "type": "quiz",
      "quiz_number": 1,
      "title": "...",
      "questions": [
        {{
          "type": "mcq",
          "question": "...",
          "options": {{"A": "...", "B": "...", "C": "...", "D": "..."}},
          "correct": "B",
          "explanation": "..."
        }},
        {{
          "type": "flashcard",
          "front": "...",
          "back": "..."
        }},
        {{
          "type": "true_false",
          "statement": "...",
          "answer": false,
          "explanation": "..."
        }}
      ]
    }},
    {{
      "type": "closing_slide",
      "title": "...",
      "narration": "closing narration text"
    }}
  ]
}}

Rules:
- Output ONLY the JSON — no markdown fences, no commentary.
- Follow the blueprint's slide order and quiz placement precisely.
- Use the exact quiz questions from the blueprint where given.
"""
        raw  = self._call(prompt, max_tokens=8192)
        data = self._parse_json(raw)

        if "course_script" in data and isinstance(data["course_script"], dict):
            data = data["course_script"]

        return CourseScript(
            course_title=data.get("course_title", course_title or source_file),
            course_description=data.get("course_description", ""),
            target_audience=target_audience,
            estimated_total_duration_min=int(data.get("estimated_total_duration_min", 12)),
            source_documents=[source_file],
            items=data.get("items", []),
        )

    def generate_micro_course_from_text(
        self,
        content_text:    str,
        course_title:    str | None = None,
        target_audience: str = "learners",
    ) -> CourseScript:
        """Generate a custom item-based course from pasted text."""
        logger.info("[text->micro] Single-call micro-course (%d chars) ...", len(content_text))
        _content = content_text[:9000]

        prompt = f"""You are an expert instructional designer.
Create a structured educational course from the SOURCE CONTENT below.
The content defines lesson sections and quiz questions — extract them faithfully.

SOURCE CONTENT:
{_content}

TARGET AUDIENCE: {target_audience}

Return ONLY a valid JSON object:
{{
  "course_title": "...",
  "course_description": "...",
  "estimated_total_duration_min": 15,
  "items": [
    {{
      "type": "slide",
      "slide_number": 1,
      "title": "...",
      "narration": "full spoken narration (minimum 150 words)",
      "bullets": ["key point 1", "key point 2", "key point 3"],
      "takeaway": "one-line key takeaway"
    }},
    {{
      "type": "quiz",
      "quiz_number": 1,
      "title": "Knowledge Check",
      "questions": [
        {{
          "type": "mcq",
          "question": "...",
          "options": {{"A": "...", "B": "...", "C": "...", "D": "..."}},
          "correct": "B",
          "explanation": "..."
        }},
        {{
          "type": "flashcard",
          "front": "term shown on front",
          "back": "definition revealed on flip"
        }},
        {{
          "type": "true_false",
          "statement": "a statement that is either true or false",
          "answer": false,
          "explanation": "..."
        }}
      ]
    }},
    {{
      "type": "closing_slide",
      "title": "Summary",
      "narration": "brief closing summary"
    }}
  ]
}}"""

        raw  = self._call(prompt, max_tokens=8192)
        data = self._parse_json(raw)
        if "course_script" in data and isinstance(data["course_script"], dict):
            data = data["course_script"]

        return CourseScript(
            course_title=data.get("course_title", course_title or "Course"),
            course_description=data.get("course_description", ""),
            target_audience=target_audience,
            estimated_total_duration_min=int(data.get("estimated_total_duration_min", 15)),
            source_documents=["inline_content"],
            items=data.get("items", []),
        )

    def generate_from_text(
        self,
        content_text:      str,
        course_title:      str | None = None,
        target_audience:   str = "learners",
        mode:              str = "detailed",
        progress_callback: "Callable[[int, int], None] | None" = None,
    ) -> CourseScript:
        """Generate a course from raw pasted text without requiring ChromaDB."""
        source_name = "inline_content"
        logger.info("[text] Generating from pasted text (%d chars, mode=%s) ...", len(content_text), mode)

        analysis = self._analyse(content_text, source_name, target_audience, {}, "English")
        outline  = self._outline(
            analysis,
            course_title or analysis.get("suggested_title", "Course"),
            target_audience, {}, "English",
        )

        if mode == "quick":
            outline["modules"] = outline["modules"][:1]
            for m in outline["modules"]:
                m["lessons"] = m["lessons"][:2]

        total_lessons = sum(len(m["lessons"]) for m in outline["modules"])
        logger.info("[text] Step 3/3: Scripting %d lessons ...", total_lessons)

        self._inline_text = content_text
        try:
            modules = self._script_all(
                outline, content_text, target_audience, source_name,
                progress_callback, {}, False, "English",
            )
        finally:
            self._inline_text = None

        total_mins = sum(l.duration_minutes for m in modules for l in m.lessons)
        return CourseScript(
            course_title=outline["course_title"],
            course_description=outline["course_description"],
            target_audience=target_audience,
            estimated_total_duration_min=total_mins,
            source_documents=[source_name],
            modules=modules,
        )
