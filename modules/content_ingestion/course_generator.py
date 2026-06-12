"""
Course script generator -- transforms document content into structured
educational scripts ready for PPT / audio / video generation pipelines.

What this does vs what a simple summariser does
------------------------------------------------
A summariser copies or compresses content.
This generator TRANSFORMS content:
  Raw manual text ->  Claude understands it -> writes as a teacher speaking to a class
  "All employees must wear PPE"  ->  "PPE is your first line of defence. Let's
   understand not just what to wear but why it protects you..."

The output is a CourseScript JSON that a downstream pipeline can consume
directly to build:
  - PowerPoint slides  (slide_bullets, slide_title)
  - Audio narration    (narration_script  ->  TTS)
  - Video              (visual_description -> scene hints for video generation)

Three-step generation (all via Claude)
---------------------------------------
1. ANALYSE   -- read all chunks from the document, identify topics + key concepts
2. OUTLINE   -- design module/lesson structure (logical progression, durations)
3. SCRIPT    -- write each lesson: narration, bullets, visuals, objectives

Usage
-----
  from modules.content_ingestion.course_generator import CourseGenerator
  from modules.content_ingestion.embedder         import Embedder
  from modules.content_ingestion.vector_store     import VectorStore
  import os

  gen = CourseGenerator(
      vector_store=VectorStore(),
      api_key=os.environ.get("ANTHROPIC_API_KEY"),
  )
  script = gen.generate(
      source_file="Safety Manual.pdf",
      course_title="Workplace Safety Essentials",
      target_audience="New employees",
  )
  script.save("course_output.json")
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


# -- Output data models ---------------------------------------------------------

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
    narration_script:        str   # full spoken text for TTS / audio
    slide_content:           SlideContent
    visual_description:      str   # scene description for video generation
    key_terms:               list[str]
    # Author Studio / GitHub frontend fields
    summary:                 str        = ""
    simplified_explanation:  str        = ""
    key_takeaways:           list[str]  = field(default_factory=list)
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
    # Flat item list used by custom/micro-course format (slides + quizzes interleaved)
    items:                        list[dict] = field(default_factory=list)

    # -- Serialisation ----------------------------------------------------------

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

        # Collect unique course-level learning objectives from all lessons (for the frontend)
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
            # Both keys present: "description" is what the Flutter frontend reads,
            # "course_description" kept for backward compatibility.
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

    def summary(self) -> str:
        lines = [
            f"Course : {self.course_title}",
            f"Audience: {self.target_audience}",
            f"Duration: {self.estimated_total_duration_min} min",
            f"Modules : {len(self.modules)}",
        ]
        for m in self.modules:
            lines.append(f"  Module {m.module_number}: {m.module_title} "
                         f"({len(m.lessons)} lessons)")
            for l in m.lessons:
                lines.append(f"    Lesson {l.lesson_number}: {l.lesson_title} "
                             f"({l.duration_minutes} min)")
        return "\n".join(lines)


# -- Generator ------------------------------------------------------------------

class CourseGenerator:
    """
    Turns any document already in the vector store into a structured
    course script using Claude as the educational content designer.
    """

    _MODEL = "claude-sonnet-4-6"

    def __init__(
        self,
        vector_store: "VectorStore",
        api_key:      str | None = None,
        model:        str | None = None,
        embedder:     "Embedder | None" = None,
    ) -> None:
        self._store       = vector_store
        self._model       = model or self._MODEL
        self._embedder    = embedder
        self._inline_text: str | None = None  # set during generate_from_text()

        key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        if not key:
            raise RuntimeError(
                "CourseGenerator requires an Anthropic API key.\n"
                "Set the ANTHROPIC_API_KEY environment variable or pass api_key=."
            )
        import anthropic
        self._client = anthropic.Anthropic(api_key=key, timeout=120.0)

    # -- Public API -------------------------------------------------------------

    def generate(
        self,
        source_file:        str,
        course_title:       str | None = None,
        target_audience:    str = "learners",
        progress_callback:  "Callable[[int, int], None] | None" = None,
        instructions:       str | None = None,
        use_knowledge_base: bool = False,
    ) -> CourseScript:
        """
        Generate a complete course script from a document already in the store.

        Parameters
        ----------
        source_file        : exact filename as stored (e.g. "Safety Manual.pdf")
        course_title       : override; auto-generated if None
        target_audience    : who the course is for ("new employees", "developers", ...)
        instructions       : additional instructions injected into every Claude prompt
        use_knowledge_base : if True, lesson context search spans all docs in the store
        """
        instructions = self._sanitize_instructions(instructions)
        logger.info("Fetching chunks for '%s' ...", source_file)
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
        if use_knowledge_base:
            logger.info("Knowledge base mode ON -- lesson context will draw from all documents.")

        # Step 1 -- analyse
        logger.info("Step 1/3: Analysing content ...")
        analysis = self._analyse(full_content, source_file, target_audience, instructions)

        # Step 2 -- outline
        logger.info("Step 2/3: Building course outline ...")
        outline = self._outline(analysis, course_title or analysis.get("suggested_title", source_file), target_audience, instructions)

        # Step 3 -- script each lesson
        logger.info("Step 3/3: Scripting %d lessons ...", sum(len(m['lessons']) for m in outline['modules']))
        modules = self._script_all(
            outline, full_content, target_audience, source_file,
            progress_callback, instructions, use_knowledge_base,
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

    def generate_micro_course(
        self,
        source_file:     str,
        instructions:    str,
        course_title:    str | None = None,
        target_audience: str = "learners",
    ) -> CourseScript:
        """
        Single-pass generation that treats `instructions` as an exact course blueprint.

        Use when instructions specify a precise structure: exact slide count, interleaved
        quizzes (MCQ / Flashcard / True-False), a specific language, or pre-written quiz
        questions.  The three-step analyse→outline→script pipeline is bypassed entirely;
        one Claude call receives the full blueprint and the source document, then returns
        a flat `items` list containing slides and quizzes in order.

        Output schema (stored in CourseScript.items):
          items: [
            { "type": "slide", "slide_number": N, "title": "...",
              "narration": "...", "bullets": [...], "takeaway": "..." },
            { "type": "quiz",  "quiz_number":  N, "title": "...",
              "questions": [
                { "type": "mcq",        "question": "...",
                  "options": {"A": "...", "B": "...", "C": "...", "D": "..."},
                  "correct": "B", "explanation": "..." },
                { "type": "flashcard",  "front": "...", "back": "..." },
                { "type": "true_false", "statement": "...",
                  "answer": false, "explanation": "..." }
              ]
            },
            { "type": "closing_slide", "title": "...", "narration": "..." }
          ]
        """
        instructions = self._sanitize_instructions(instructions)
        logger.info("[custom] Fetching chunks for '%s' ...", source_file)
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
        logger.info("[custom] %d chunks loaded (%d chars). Generating from blueprint ...", len(chunks), len(full_content))

        # Build the prompt — double-braces to escape literals inside f-string
        prompt = f"""You are an expert instructional designer.
Generate a complete educational course by following the COURSE BLUEPRINT below EXACTLY.
Every structural rule, language requirement, slide count, quiz placement, question text,
and answer specified in the blueprint must be reproduced faithfully in the output.

===========  COURSE BLUEPRINT  ===========
{instructions}
==========================================

TARGET AUDIENCE: {target_audience}

SOURCE DOCUMENT — use this as your factual knowledge base to write narrations and bullets:
{full_content[:9000]}

Return the complete course as a single JSON object using this schema:
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
- Preserve all non-ASCII characters (Devanagari, accented letters, emojis) exactly.
- Follow the blueprint's slide order and quiz placement precisely.
- Use the exact quiz questions, options, and answers from the blueprint where given.
"""
        raw = self._call(
            prompt,
            system=(
                "You are an expert instructional designer. "
                "You follow blueprint instructions exactly and always return valid JSON. "
                "Never deviate from the specified structure, language, content, or quiz requirements."
            ),
            max_tokens=8192,
        )
        data = self._parse_json(raw)

        # Some blueprints tell Claude to wrap items under a "course_script" key
        # (e.g. {"source_file": ..., "course_script": {"course_title": ..., "items": [...]}}).
        # Unwrap that layer so the rest of the code always sees a flat dict.
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
    ) -> "CourseScript":
        """
        Generate a custom (item-based) course from pasted text in a single Claude call.

        Produces a flat items[] array:
            slide → slide → ... → quiz (MCQ + Flashcard + True-False) → closing_slide

        Used automatically when content_text contains [MCQ], [FLASHCARD], or [TRUE/FALSE]
        markers — bypasses the module/lesson pipeline entirely.
        """
        logger.info("[text->micro] Single-call micro-course (%d chars) ...", len(content_text))

        if len(content_text) > 9000:
            logger.warning(
                "content_text truncated from %d to 9000 chars for micro-course generation.",
                len(content_text),
            )
        _content = content_text[:9000]

        prompt = f"""You are an expert instructional designer.
Create a structured educational course from the SOURCE CONTENT below.
The content already defines the lesson sections and quiz questions — extract them faithfully.

SOURCE CONTENT:
{_content}

TARGET AUDIENCE: {target_audience}

INSTRUCTIONS:
- Create one "slide" item per lesson/section in the content (in order)
- Place ALL quiz questions in a single "quiz" item at the end, BEFORE the closing_slide
- Identify each question type from its marker: [MCQ], [FLASHCARD], [TRUE/FALSE]
- For MCQ: mark the option labelled [CORRECT] as the "correct" key (A/B/C/D)
- For Flashcard: FRONT text → "front", BACK text → "back"
- For True/False: extract statement and answer (true/false boolean)

Return ONLY a valid JSON object — no markdown fences, no commentary:
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
          "front": "term or question shown on front",
          "back": "definition or answer revealed on flip"
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
        """
        Generate a course from raw pasted text without requiring ChromaDB.

        Used by the Author Studio frontend (GitHub) which sends content_text
        directly instead of an uploaded file.  The three-step pipeline
        (analyse → outline → script) runs identically, but the vector-store
        lookup is bypassed — self._inline_text is used as the context source.

        mode='quick'    → 1 module, max 2 lessons (fast preview)
        mode='detailed' → full outline (2-4 modules, 2-4 lessons each)
        """
        source_name = "inline_content"
        logger.info("[text] Generating from pasted text (%d chars, mode=%s) ...", len(content_text), mode)

        # Step 1 -- analyse
        logger.info("[text] Step 1/3: Analysing ...")
        analysis = self._analyse(content_text, source_name, target_audience)

        # Step 2 -- outline
        logger.info("[text] Step 2/3: Building outline ...")
        outline = self._outline(
            analysis,
            course_title or analysis.get("suggested_title", "Course"),
            target_audience,
        )

        # Trim outline for quick mode
        if mode == "quick":
            outline["modules"] = outline["modules"][:1]
            for m in outline["modules"]:
                m["lessons"] = m["lessons"][:2]

        total_lessons = sum(len(m["lessons"]) for m in outline["modules"])
        logger.info("[text] Step 3/3: Scripting %d lessons ...", total_lessons)

        # Step 3 -- script each lesson, bypassing vector store
        self._inline_text = content_text
        try:
            modules = self._script_all(
                outline, content_text, target_audience, source_name,
                progress_callback, None, False,
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

    # -- Sanitization -----------------------------------------------------------

    # Strip ASCII control chars (keep \n \r \t) to block prompt-injection via instructions.
    _CTRL_CHAR_RE      = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
    _MAX_INSTRUCTIONS  = 2_000   # chars; truncate with a warning beyond this

    @classmethod
    def _sanitize_instructions(cls, text: str | None) -> str | None:
        if not text:
            return text
        text = cls._CTRL_CHAR_RE.sub("", text)
        if len(text) > cls._MAX_INSTRUCTIONS:
            logger.warning(
                "instructions truncated from %d to %d chars.",
                len(text), cls._MAX_INSTRUCTIONS,
            )
            text = text[: cls._MAX_INSTRUCTIONS]
        return text.strip() or None

    # -- Claude call helpers ----------------------------------------------------

    # ~4 chars per token; keep well under the 200k-token API limit.
    _MAX_INPUT_CHARS = 600_000

    def _call(self, prompt: str, system: str = "", max_tokens: int = 4096) -> str:
        system_text = system or (
            "You are an expert instructional designer who transforms raw "
            "document content into engaging, clear educational material. "
            "You always return valid JSON when asked."
        )
        total_chars = len(prompt) + len(system_text)
        if total_chars > self._MAX_INPUT_CHARS:
            raise ValueError(
                f"Prompt is too large for the Claude API: {total_chars:,} chars "
                f"(≈{total_chars // 4:,} tokens). Reduce the source document size "
                "or split the course into smaller sections."
            )

        msgs = [{"role": "user", "content": prompt}]
        resp = self._client.messages.create(
            model=self._model,
            max_tokens=max_tokens,
            system=system_text,
            messages=msgs,
        )
        return resp.content[0].text

    def _parse_json(self, text: str) -> dict:
        """Extract and parse JSON from a response that may be wrapped in markdown fences."""
        text = text.strip()

        # Fast path: response is already clean JSON
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        # Strip markdown fences (```json...``` or ```...```)
        if "```" in text:
            for fence in ("```json", "```"):
                if fence in text:
                    after_fence = text[text.index(fence) + len(fence):]
                    end = after_fence.find("```")
                    candidate = after_fence[:end].strip() if end != -1 else after_fence.strip()
                    try:
                        return json.loads(candidate)
                    except json.JSONDecodeError:
                        break

        # Last resort: find the outermost {...} in the response
        start = text.find("{")
        end   = text.rfind("}") + 1
        if start != -1 and end > start:
            try:
                return json.loads(text[start:end])
            except json.JSONDecodeError as exc:
                raise ValueError(
                    f"Could not parse JSON from model response. "
                    f"Parse error: {exc}. "
                    f"Response (first 300 chars): {text[:300]!r}"
                ) from exc

        raise ValueError(
            f"No JSON object found in model response. "
            f"Response (first 300 chars): {text[:300]!r}"
        )

    # -- Relevant chunk retrieval -----------------------------------------------

    def _get_lesson_context(
        self,
        topic_focus:        str,
        source_file:        str,
        fallback_content:   str,
        n_chunks:           int = 8,
        use_knowledge_base: bool = False,
    ) -> str:
        """Return the most semantically relevant chunks for a lesson topic.

        When self._inline_text is set (generate_from_text path), the raw text
        is used directly and the vector store is bypassed entirely.

        When use_knowledge_base is True, searches across all documents in the
        store (no source_file filter), enriching the lesson with supporting
        content from the whole knowledge base.

        Falls back to the first 5 000 chars of the full document text when no
        embedder is available.
        """
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

    # -- Step 1: Analyse --------------------------------------------------------

    def _analyse(self, content: str, source_file: str, audience: str, instructions: str | None = None) -> dict:
        instructions_block = (
            f"\nADDITIONAL INSTRUCTIONS FROM COURSE CREATOR:\n{instructions}\n"
            if instructions else ""
        )
        prompt = f"""
Analyse the following document content extracted from "{source_file}".

TARGET AUDIENCE: {audience}
{instructions_block}
DOCUMENT CONTENT:
{content[:6000]}

Return a JSON object with:
{{
  "suggested_title": "short course title based on content",
  "document_type": "safety manual / technical guide / process document / etc.",
  "main_topics": ["topic 1", "topic 2", ...],
  "key_concepts": ["concept 1", "concept 2", ...],
  "difficulty_level": "beginner / intermediate / advanced",
  "content_summary": "2-3 sentence summary of what this document covers"
}}

Return ONLY the JSON, no other text.
"""
        raw = self._call(prompt)
        return self._parse_json(raw)

    # -- Step 2: Outline --------------------------------------------------------

    def _outline(self, analysis: dict, course_title: str, audience: str, instructions: str | None = None) -> dict:
        instructions_block = (
            f"\nADDITIONAL INSTRUCTIONS FROM COURSE CREATOR:\n{instructions}\n"
            if instructions else ""
        )
        prompt = f"""
You are designing a course based on this content analysis:

{json.dumps(analysis, indent=2)}

COURSE TITLE: {course_title}
TARGET AUDIENCE: {audience}
{instructions_block}
Design a course outline. Rules:
- 2 to 4 modules
- 2 to 4 lessons per module
- Each lesson: 5-10 minutes of content
- Progress logically: fundamentals first, then application, then advanced
- Lessons must BUILD on each other -- not repeat content

Return a JSON object:
{{
  "course_title": "{course_title}",
  "course_description": "2-sentence course description",
  "modules": [
    {{
      "module_number": 1,
      "module_title": "...",
      "module_description": "one sentence",
      "lessons": [
        {{
          "lesson_number": 1,
          "lesson_title": "...",
          "topic_focus": "what specific topic this lesson covers",
          "duration_minutes": 7
        }}
      ]
    }}
  ]
}}

Return ONLY the JSON.
"""
        raw = self._call(prompt)
        return self._parse_json(raw)

    # -- Step 3: Script each lesson ---------------------------------------------

    def _script_all(
        self,
        outline:            dict,
        content:            str,
        audience:           str,
        source_file:        str,
        progress_callback:  "Callable[[int, int], None] | None" = None,
        instructions:       str | None = None,
        use_knowledge_base: bool = False,
    ) -> list[ModuleScript]:
        total = sum(len(m["lessons"]) for m in outline["modules"])
        done  = 0
        modules_out: list[ModuleScript] = []
        for mod in outline["modules"]:
            lessons_out: list[LessonScript] = []
            for les in mod["lessons"]:
                ls = self._script_lesson(les, mod, content, audience, source_file, instructions, use_knowledge_base)
                lessons_out.append(ls)
                done += 1
                if progress_callback:
                    progress_callback(done, total)
                logger.info("  [ok] (%d/%d) %s > %s", done, total, mod['module_title'], les['lesson_title'])
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
        instructions:       str | None = None,
        use_knowledge_base: bool = False,
    ) -> LessonScript:
        context = self._get_lesson_context(
            lesson["topic_focus"], source_file, content, use_knowledge_base=use_knowledge_base,
        )
        instructions_block = (
            f"\nADDITIONAL INSTRUCTIONS FROM COURSE CREATOR:\n{instructions}\n"
            if instructions else ""
        )
        prompt = f"""
You are scripting ONE lesson for an educational course.

MODULE: {module['module_title']}
LESSON: {lesson['lesson_title']}
TOPIC FOCUS: {lesson['topic_focus']}
DURATION: {lesson['duration_minutes']} minutes
TARGET AUDIENCE: {audience}
{instructions_block}
SOURCE DOCUMENT CONTENT (use this as your knowledge base):
{context}

IMPORTANT RULES:
1. narration_script: Write as a teacher SPEAKING to the class. Natural, engaging,
   first-person plural ("Let's explore...", "Think of it this way...").
   Do NOT just read the document -- explain, give examples, make it memorable.
   Length: ~{lesson['duration_minutes'] * 120} words (matches audio duration).
2. slide_bullets: 3-5 concise bullet points for the PowerPoint slide.
   Short phrases, not sentences. What a learner glances at while listening.
3. speaker_notes: 1-2 sentences the presenter says while showing this slide.
4. visual_description: What should appear in the video?
   Example: "Animation showing data flowing through three processing stages"
5. learning_objectives: 2-3 "By the end of this lesson, you will be able to..." statements.
6. key_terms: 3-5 important vocabulary words from this lesson.
7. summary: 1-2 sentence overview of what this lesson covers.
8. simplified_explanation: The core concept explained in plain language (2-3 sentences).
9. key_takeaways: 3-4 main actionable points the learner should remember.
10. real_world_examples: 2-3 practical examples each with a situation and correct_action.
11. safety_scenarios: 2-3 safety-relevant scenarios (leave empty list [] if not applicable).

Return a JSON object:
{{
  "learning_objectives": ["...", "..."],
  "narration_script": "Full spoken text...",
  "slide_content": {{
    "title": "{lesson['lesson_title']}",
    "bullets": ["point 1", "point 2", "point 3"],
    "speaker_notes": "..."
  }},
  "visual_description": "...",
  "key_terms": ["term1", "term2"],
  "summary": "1-2 sentence lesson summary.",
  "simplified_explanation": "Plain-language explanation...",
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
        raw = self._call(prompt, max_tokens=8192)
        data = self._parse_json(raw)

        slide = SlideContent(
            title=data["slide_content"]["title"],
            bullets=data["slide_content"].get("bullets", []),
            speaker_notes=data["slide_content"].get("speaker_notes", ""),
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
