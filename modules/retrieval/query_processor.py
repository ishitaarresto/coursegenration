"""
modules/retrieval/query_processor.py -- Intent detection, query rewriting,
contextual rewriting.

A single Claude Haiku call does three things at once:
  1. Detect intent  (factual | procedural | summary | quiz | conversational)
  2. Detect language (ISO 639-1 code)
  3. Rewrite query  (fix ASR errors, filler words, extract key terms)

For conversational follow-ups (pronouns like "it", "that", "what about that"),
a second Haiku call resolves the reference using recent history.

Both calls use claude-haiku-4-5-20251001 — fast and cheap, under 50ms each.

Intent routing (applied in pipeline.py):
  factual | procedural  -> full hybrid search + rerank
  conversational        -> contextual rewrite -> full hybrid search + rerank
  summary               -> skip search, Claude uses lesson narration from system prompt
  quiz                  -> skip search, redirect learner to the /quiz endpoint
"""
from __future__ import annotations

import json
import re

INTENT_FACTUAL        = "factual"
INTENT_PROCEDURAL     = "procedural"
INTENT_SUMMARY        = "summary"
INTENT_QUIZ           = "quiz"
INTENT_CONVERSATIONAL = "conversational"

_ALL_INTENTS = {
    INTENT_FACTUAL, INTENT_PROCEDURAL,
    INTENT_SUMMARY, INTENT_QUIZ, INTENT_CONVERSATIONAL,
}

_PROCESS_SYSTEM = """\
You are a query processor for a multilingual e-learning voice assistant.

Analyse the learner's input and return a JSON object with exactly these fields:
  "intent"      : one of ["factual", "procedural", "summary", "quiz", "conversational"]
  "language"    : ISO 639-1 code of the input language (e.g. "en", "hi", "ar", "fr")
  "clean_query" : rewritten query — fix ASR errors, remove filler words ("umm", "like"),
                  extract key concepts. KEEP the same language as the input. Do NOT translate.

Intent definitions:
  factual        — asking what/why/explain ("what is arc flash?")
  procedural     — asking how to do something step-by-step ("how do I apply LOTO?")
  summary        — asking for a recap or summary of a lesson or topic
  quiz           — asking to be tested or quizzed on material
  conversational — short follow-up that references something from recent conversation
                   (pronoun-heavy: "it", "that", "this", or very short / ambiguous phrasing)

Return ONLY valid JSON. No markdown, no explanation, no code fences.\
"""

_CONTEXT_SYSTEM = (
    "You resolve conversational follow-up queries. "
    "Return only the rewritten query — no explanation, no punctuation changes."
)

_CONTEXT_USER = """\
RECENT CONVERSATION (last {n} turns):
{history}

FOLLOW-UP QUERY: {query}

Rewrite the follow-up as a fully self-contained question in the SAME language as the query.
Replace all pronouns (it, that, this, they, those) with the actual subject from the history.\
"""


class QueryProcessor:

    def __init__(self, api_key: str, model: str = "claude-haiku-4-5-20251001") -> None:
        import anthropic
        self._client = anthropic.Anthropic(api_key=api_key, timeout=30.0)
        self._model  = model

    def _call(self, system: str, user: str) -> str:
        resp = self._client.messages.create(
            model=self._model,
            max_tokens=256,
            system=system,
            messages=[{"role": "user", "content": user}],
        )
        return resp.content[0].text.strip()

    def process(self, query: str) -> dict[str, str]:
        """
        Returns {"intent": str, "language": str, "clean_query": str}.
        Falls back to factual/en/original_query on any error.
        """
        try:
            raw = self._call(_PROCESS_SYSTEM, query)
            # Strip code fences if the model wraps output
            raw = re.sub(r"```(?:json)?\s*", "", raw).strip("`").strip()
            data = json.loads(raw)
            intent = data.get("intent", INTENT_FACTUAL)
            if intent not in _ALL_INTENTS:
                intent = INTENT_FACTUAL
            return {
                "intent":      intent,
                "language":    data.get("language", "en"),
                "clean_query": data.get("clean_query", query) or query,
            }
        except Exception:
            return {"intent": INTENT_FACTUAL, "language": "en", "clean_query": query}

    def contextual_rewrite(
        self,
        query:   str,
        history: list[dict],
        n_turns: int = 3,
    ) -> str:
        """
        Resolve pronouns in a follow-up using the last n_turns of conversation history.
        Returns the rewritten standalone query; falls back to original on error.
        """
        if not history:
            return query

        recent = history[-(n_turns * 2):]
        history_text = "\n".join(
            f"{m['role'].upper()}: {m['content'][:300]}" for m in recent
        )
        try:
            return self._call(
                _CONTEXT_SYSTEM,
                _CONTEXT_USER.format(
                    n=len(recent) // 2,
                    history=history_text,
                    query=query,
                ),
            )
        except Exception:
            return query
