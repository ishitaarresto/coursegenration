"""
modules/tutor/tutor_engine.py -- Claude-powered AI Tutor engine.

Responsibilities:
  chat()            -- multi-turn RAG-augmented conversation with session memory
  generate_quiz()   -- produce MCQ questions from current lesson content
  evaluate_answer() -- check a learner's answer and return explanation
"""

from __future__ import annotations
import logging

logger = logging.getLogger("arresto.tutor.engine")

import json
import random
import re
import uuid
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from modules.tutor.session_store import TutorSession, TutorSessionStore


# -- Fallback quiz builder (no API required) ------------------------------------

def _extract_defining_sentence(term: str, narration: str) -> str | None:
    """Return the first sentence in narration that contains and defines the term."""
    for sentence in re.split(r"(?<=[.!?])\s+", narration):
        s = sentence.strip()
        if term.lower() in s.lower() and len(s) > 40:
            return s[:200]
    return None


def _strip_objective_prefix(obj: str) -> str:
    return re.sub(
        r"^By the end of (this lesson|this module)[,\s]+you will be able to\s*",
        "", obj, flags=re.IGNORECASE,
    ).strip().rstrip(".")


# Generic wrong statements plausible in any safety lesson (used as padding distractors)
_GENERIC_WRONG = [
    "PPE alone is sufficient to eliminate all electrical risks without other controls",
    "Electrical accidents only occur when workers are unqualified or untrained",
    "A permit-to-work is only required for high-voltage systems above 33 kV",
    "Routine visual inspection is always sufficient to verify insulation integrity",
    "Earthing is only required for outdoor electrical installations",
    "Arc flash hazards only exist when the electrical supply is switched on",
]


def _build_opts(correct: str, wrong: list[str]) -> tuple[dict, str]:
    """Return (options_dict, correct_letter) with shuffled A-D options."""
    pool = [correct] + wrong[:3]
    while len(pool) < 4:
        pool.append(_GENERIC_WRONG[len(pool) - 1])
    random.shuffle(pool)
    opts = {chr(65 + i): v for i, v in enumerate(pool[:4])}
    correct_letter = next(k for k, v in opts.items() if v == correct)
    return opts, correct_letter


def _generate_quiz_from_lesson(
    lessons: list[dict],
    num_questions: int,
    quiz_type: str,
) -> list[dict]:
    """
    Produce MCQ questions from lesson script data with no external API call.

    Three question formats:
      1. Objective recall  — "Which skill does this lesson develop?"
      2. Key term ID       — "Which term describes: '<definition>'?"
      3. Fact recall       — "Which statement about X is CORRECT?"
    """
    pool: list[dict] = []

    for lesson in lessons:
        title      = lesson.get("lesson_title", "this lesson")
        narration  = lesson.get("narration_script", "")
        objectives = lesson.get("learning_objectives", [])
        key_terms  = lesson.get("key_terms", [])
        bullets    = lesson.get("slide_content", {}).get("bullets", [])

        # --- Format 1: objective recall ---
        for i, obj in enumerate(objectives):
            ability = _strip_objective_prefix(obj).capitalize()
            wrong   = [
                _strip_objective_prefix(o).capitalize()
                for j, o in enumerate(objectives) if j != i
            ] + [
                "Memorise regulatory code numbers without understanding their purpose",
                "Perform unsupervised maintenance without a valid work permit",
            ]
            opts, letter = _build_opts(ability, wrong)
            pool.append({
                "question":       f"Which of the following abilities is a learning outcome of the '{title}' lesson?",
                "options":        opts,
                "correct_answer": letter,
                "explanation":    f"This lesson specifically develops the ability to {ability.lower()}.",
                "topic_tag":      "learning objectives",
            })

        # --- Format 2: key term identification ---
        for i, term in enumerate(key_terms):
            definition = _extract_defining_sentence(term, narration)
            if not definition:
                continue
            snippet = definition if len(definition) <= 130 else definition[:130] + "…"
            other_terms = [t for j, t in enumerate(key_terms) if j != i]
            wrong = other_terms[:3] + ["None of the above"]
            opts, letter = _build_opts(term, wrong)
            pool.append({
                "question":       f"Which key concept does the following describe?\n\"{snippet}\"",
                "options":        opts,
                "correct_answer": letter,
                "explanation":    f"{term} — {definition}",
                "topic_tag":      term,
            })

        # --- Format 3: fact recall — correct bullet vs generic wrong distractors ---
        for i, bullet in enumerate(bullets[:3]):   # limit to 3 to avoid too many similar Qs
            wrong = [g for g in _GENERIC_WRONG if g not in bullets][:3]
            opts, letter = _build_opts(bullet, wrong)
            pool.append({
                "question":       f"Which of the following statements about '{title}' is CORRECT?",
                "options":        opts,
                "correct_answer": letter,
                "explanation":    f"'{bullet}' is a verified fact from this lesson. The other options are common misconceptions.",
                "topic_tag":      title,
            })

    random.shuffle(pool)
    return pool[:num_questions]

# Keep last 10 user/assistant exchanges in the API call (20 messages).
# Older turns stay in session.history for the /history endpoint but are
# dropped from the Claude context to avoid hitting token limits.
_MAX_HISTORY_PAIRS = 10


_INTENT_QUIZ    = "quiz"
_INTENT_SUMMARY = "summary"


class TutorEngine:
    _MODEL = "claude-opus-4-8"

    def __init__(
        self,
        api_key:            str,
        vector_store:       Any,
        embedder:           Any = None,
        model:              str | None = None,
        retrieval_pipeline: Any = None,
        progress_tracker:   Any = None,
    ) -> None:
        self._store              = vector_store
        self._embedder           = embedder
        self._model              = model or self._MODEL
        self._retrieval_pipeline = retrieval_pipeline
        self._progress_tracker   = progress_tracker

        import anthropic
        self._client = anthropic.Anthropic(api_key=api_key, timeout=120.0)

    # -- System prompt ----------------------------------------------------------

    def _build_system_prompt(
        self,
        session: "TutorSession",
        language: str = "en",
        weak_topics: list[str] | None = None,
    ) -> str:
        lesson = session.get_current_lesson_data()
        module = session.get_current_module_data()

        lesson_block = ""
        if lesson:
            objectives = "\n".join(
                f"  - {o}" for o in lesson.get("learning_objectives", [])
            )
            key_terms = ", ".join(lesson.get("key_terms", []))
            narration  = lesson.get("narration_script", "")[:3000]
            mod_title  = module["module_title"] if module else ""
            lesson_block = f"""
CURRENT LESSON:
  Module {session.current_module}: {mod_title}
  Lesson {session.current_lesson}: {lesson['lesson_title']}
  Duration: {lesson.get('duration_minutes', '?')} minutes

Learning Objectives:
{objectives}

Key Terms: {key_terms}

Lesson Content (use as your primary knowledge source):
{narration}
"""

        lang_instruction = ""
        if language and language != "en":
            lang_instruction = (
                f"\nLANGUAGE: The learner's message is in '{language}'. "
                "Respond in the same language as the learner's message."
            )

        weak_block = ""
        if weak_topics:
            topics_str = ", ".join(weak_topics)
            weak_block = (
                f"\nLEARNER WEAK AREAS: {topics_str}\n"
                "(Give extra attention and clearer explanations to these topics when they arise.)"
            )

        return f"""You are an expert AI Learning Tutor for the course "{session.course_title}".
Your learners are: {session.target_audience}

Your behaviour:
- Teach, don't just recite. Explain concepts clearly, use examples and analogies suited to the learner's role.
- When a learner is confused, give a hint first, then the full explanation if they're still stuck.
- When asked to simplify, use plain language and real-world examples.
- When asked for a summary, give a concise bullet-point recap of the key points.
- Keep answers focused and practical — no unnecessary padding.
- Stay on topic. If asked something unrelated, politely redirect to the course material.
- Always be encouraging and supportive.
{lang_instruction}
{weak_block}
{lesson_block}"""

    # -- RAG context ------------------------------------------------------------

    def _get_rag_context(self, query: str, source_file: str, n_chunks: int = 5) -> str:
        if not self._embedder:
            return ""
        try:
            q_vec = self._embedder.embed_query(query)
            hits  = self._store.query(q_vec, n_results=n_chunks, source_file=source_file)
            if not hits:
                return ""
            return "\n\n".join(
                f"[{h['metadata'].get('section_heading', '')}]\n{h['text']}"
                for h in hits
            )
        except Exception:
            return ""

    # -- History trimming -------------------------------------------------------

    def _trim_history(self, history: list[dict]) -> list[dict]:
        limit = _MAX_HISTORY_PAIRS * 2
        return history[-limit:] if len(history) > limit else list(history)

    # -- Public methods ---------------------------------------------------------

    def chat(
        self,
        session: "TutorSession",
        user_message: str,
        store: "TutorSessionStore",
    ) -> str:
        """Process a learner message and return the tutor's reply."""
        import time

        language    = "en"
        rag_context = ""

        if self._retrieval_pipeline:
            # Phases 1-5: intelligent retrieval
            result = self._retrieval_pipeline.retrieve(
                user_message,
                source_file=session.source_file,
                history=session.history,
            )
            language = result.language

            # Quiz intent — no RAG needed, redirect to the dedicated endpoint
            if result.skipped and result.intent == _INTENT_QUIZ:
                reply = (
                    "It looks like you'd like to be tested! "
                    "Use the **Quiz** endpoint (POST /api/v1/tutor/session/{id}/quiz) "
                    "to generate multiple-choice questions for your current lesson."
                )
                session.history.append({"role": "user",      "content": user_message})
                session.history.append({"role": "assistant", "content": reply})
                session.updated_at = time.time()
                store.save()
                return reply

            # Summary intent — lesson narration is already in the system prompt;
            # Claude can summarise from there without retrieval context
            if result.chunks:
                rag_context = "\n\n".join(
                    f"[{c['metadata'].get('section_heading', '')}]\n{c['text']}"
                    for c in result.chunks
                )
        else:
            # Fallback: basic MiniLM dense retrieval
            rag_context = self._get_rag_context(user_message, session.source_file)

        if rag_context:
            augmented_message = (
                f"[RELEVANT CONTENT FROM COURSE MATERIALS]\n{rag_context}\n"
                f"[END CONTEXT]\n\nLearner: {user_message}"
            )
        else:
            augmented_message = user_message

        messages = self._trim_history(session.history) + [
            {"role": "user", "content": augmented_message}
        ]

        weak_topics: list[str] = []
        if self._progress_tracker and session.learner_id != "anonymous":
            weak_topics = self._progress_tracker.get_weak_topic_names(
                session.learner_id, session.source_file
            )

        resp = self._client.messages.create(
            model=self._model,
            max_tokens=1024,
            system=self._build_system_prompt(session, language=language, weak_topics=weak_topics),
            messages=messages,
        )
        reply = resp.content[0].text

        # Store the raw user message (not the RAG-augmented version) in history
        session.history.append({"role": "user",      "content": user_message})
        session.history.append({"role": "assistant", "content": reply})
        session.updated_at = time.time()
        store.save()

        return reply

    def generate_quiz(
        self,
        session: "TutorSession",
        num_questions: int,
        store: "TutorSessionStore",
    ) -> list[dict]:
        """Generate MCQ questions for the current lesson. Correct answers stored server-side."""
        import time

        lesson = session.get_current_lesson_data()
        if lesson:
            content      = lesson.get("narration_script", "")[:4000]
            lesson_title = lesson["lesson_title"]
            key_terms    = ", ".join(lesson.get("key_terms", []))
        else:
            rag_content  = self._get_rag_context(
                f"key concepts {session.course_title}", session.source_file, n_chunks=6
            )
            content      = rag_content or f"Course: {session.course_title}"
            lesson_title = session.course_title
            key_terms    = ""

        key_terms_line = f"Key Terms to test: {key_terms}" if key_terms else ""

        prompt = f"""Generate {num_questions} multiple choice quiz questions for the following lesson.

LESSON: {lesson_title}
TARGET AUDIENCE: {session.target_audience}
{key_terms_line}

LESSON CONTENT:
{content}

Rules:
- Test genuine understanding, not just memorisation
- 4 options per question (A, B, C, D)
- One clearly correct answer per question
- Wrong options must be plausible but clearly incorrect to a learner who understood the lesson
- Include a concise explanation (2-3 sentences) of why the correct answer is right

Return a JSON array — no other text:
[
  {{
    "question": "...",
    "options": {{
      "A": "...",
      "B": "...",
      "C": "...",
      "D": "..."
    }},
    "correct_answer": "A",
    "explanation": "..."
  }}
]"""

        try:
            raw = self._client.messages.create(
                model=self._model,
                max_tokens=2048,
                system="You are an expert quiz designer for workplace safety training. Always return valid JSON.",
                messages=[{"role": "user", "content": prompt}],
            )
            text = raw.content[0].text.strip()
            if "```" in text:
                start = text.find("[", text.find("```"))
                end   = text.rfind("]") + 1
                text  = text[start:end]
            questions_data = json.loads(text)
        except Exception as api_err:
            # Fall back to script-based generation (no API credits needed)
            logger.warning("API quiz generation failed (%s), falling back to script-based quiz.", api_err)
            questions_data = _generate_quiz_from_lesson(
                [lesson] if lesson else [], num_questions, "manual"
            )
            # script-based already returns final dicts with correct_answer + explanation
            client_questions = []
            for q in questions_data[:num_questions]:
                qid = str(uuid.uuid4())
                from modules.tutor.session_store import QuizQuestion
                session.add_quiz_question(QuizQuestion(
                    question_id=qid,
                    question=q["question"],
                    options=list(q["options"].values()),
                    correct_answer=q["correct_answer"],
                    explanation=q["explanation"],
                    topic_tag=q.get("topic_tag", ""),
                ))
                client_questions.append({
                    "question_id": qid,
                    "question":    q["question"],
                    "options":     q["options"],
                })
            session.updated_at = time.time()
            store.save()
            return client_questions

        client_questions = []
        for q in questions_data[:num_questions]:
            qid = str(uuid.uuid4())
            from modules.tutor.session_store import QuizQuestion
            session.add_quiz_question(QuizQuestion(
                question_id=qid,
                question=q["question"],
                options=list(q["options"].values()),
                correct_answer=q["correct_answer"],
                explanation=q["explanation"],
            ))
            # Return options as A/B/C/D dict — correct_answer is NOT included
            client_questions.append({
                "question_id": qid,
                "question":    q["question"],
                "options":     q["options"],
            })

        session.updated_at = time.time()
        store.save()
        return client_questions

    def generate_checkpoint_quiz(
        self,
        session: "TutorSession",
        num_questions: int,
        quiz_type: str,  # "lesson_checkpoint" | "module_checkpoint"
        store: "TutorSessionStore",
    ) -> list[dict]:
        """Generate a gated checkpoint quiz for a lesson or module."""
        import time

        if quiz_type == "module_checkpoint":
            module = session.get_current_module_data()
            all_narration: list[str] = []
            all_key_terms: list[str] = []
            for les in (module.get("lessons", []) if module else []):
                snippet = les.get("narration_script", "")[:1500]
                all_narration.append(
                    f"Lesson {les['lesson_number']}: {les['lesson_title']}\n{snippet}"
                )
                all_key_terms.extend(les.get("key_terms", []))
            content      = "\n\n".join(all_narration)[:5000]
            lesson_title = (
                f"Module {session.current_module}: {module['module_title']}"
                if module else session.course_title
            )
        else:
            lesson  = session.get_current_lesson_data()
            module  = session.get_current_module_data()
            if lesson:
                content      = lesson.get("narration_script", "")[:4000]
                lesson_title = lesson["lesson_title"]
                all_key_terms = lesson.get("key_terms", [])
            else:
                content      = f"Course: {session.course_title}"
                lesson_title = session.course_title
                all_key_terms = []

        key_terms_line = f"Key Terms: {', '.join(all_key_terms)}" if all_key_terms else ""

        prompt = f"""Generate {num_questions} multiple choice quiz questions for the following lesson.

LESSON: {lesson_title}
TARGET AUDIENCE: {session.target_audience}
{key_terms_line}

CONTENT:
{content}

Rules:
- Test genuine understanding, not just memorisation
- 4 options per question (A, B, C, D)
- One clearly correct answer per question
- Wrong options must be plausible but clearly incorrect to a learner who understood
- Include a concise explanation (2-3 sentences) of why the correct answer is right
- Each question must include a "topic_tag" naming the specific concept or key term being tested

Return a JSON array — no other text:
[
  {{
    "question": "...",
    "options": {{"A": "...", "B": "...", "C": "...", "D": "..."}},
    "correct_answer": "A",
    "explanation": "...",
    "topic_tag": "name of the concept or key term tested"
  }}
]"""

        try:
            raw = self._client.messages.create(
                model=self._model,
                max_tokens=2048,
                system="You are an expert quiz designer. Always return valid JSON.",
                messages=[{"role": "user", "content": prompt}],
            )
            text = raw.content[0].text.strip()
            if "```" in text:
                start = text.find("[", text.find("```"))
                end   = text.rfind("]") + 1
                text  = text[start:end]
            questions_data = json.loads(text)
        except Exception as api_err:
            logger.warning("API checkpoint quiz failed (%s), falling back to script-based quiz.", api_err)
            source_lessons = (
                module.get("lessons", []) if quiz_type == "module_checkpoint" and module else
                ([lesson] if lesson else [])
            )
            questions_data = _generate_quiz_from_lesson(source_lessons, num_questions, quiz_type)

        client_questions: list[dict] = []
        checkpoint_qids: list[str]   = []

        for q in questions_data[:num_questions]:
            qid = str(uuid.uuid4())
            from modules.tutor.session_store import QuizQuestion
            session.add_quiz_question(QuizQuestion(
                question_id=qid,
                question=q["question"],
                options=list(q["options"].values()),
                correct_answer=q["correct_answer"],
                explanation=q["explanation"],
                quiz_type=quiz_type,
                topic_tag=q.get("topic_tag", ""),
            ))
            checkpoint_qids.append(qid)
            client_questions.append({
                "question_id": qid,
                "question":    q["question"],
                "options":     q["options"],
            })

        if not checkpoint_qids:
            # No questions generated (lesson data missing) — auto-pass the checkpoint
            session.awaiting_checkpoint         = False
            session.current_lesson_checkpointed = True
        else:
            session.awaiting_checkpoint         = True
            session.checkpoint_type             = quiz_type
            session.pending_checkpoint_qids     = checkpoint_qids
            session.checkpoint_answers          = []
            session.current_lesson_checkpointed = False
        session.updated_at = time.time()
        store.save()

        return client_questions

    def evaluate_answer(
        self,
        session: "TutorSession",
        question_id: str,
        learner_answer: str,
        store: "TutorSessionStore",
    ) -> dict:
        """Evaluate a learner's MCQ answer. No extra Claude call needed."""
        import time

        q = session.get_quiz_question(question_id)
        if not q:
            raise ValueError(
                f"Question '{question_id}' not found. "
                "It may have already been answered or the session has changed."
            )

        correct = learner_answer.strip().upper() == q.correct_answer.strip().upper()

        tutor_reply = (
            f"{'Correct!' if correct else f'Not quite — the correct answer is {q.correct_answer}.'} "
            f"{q.explanation}"
        )

        # Log the quiz exchange to conversation history
        session.history.append({
            "role": "user",
            "content": f"[Quiz] {q.question} — My answer: {learner_answer.upper()}",
        })
        session.history.append({
            "role": "assistant",
            "content": tutor_reply,
        })

        session.remove_quiz_question(question_id)
        session.updated_at = time.time()
        store.save()

        return {
            "correct":        correct,
            "correct_answer": q.correct_answer,
            "explanation":    q.explanation,
        }
