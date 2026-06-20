"""
modules/retrieval/reranker.py -- Cross-encoder reranker (top-20 -> top-5).

Bi-encoders (bge-m3, MiniLM) embed query and document independently and
compare their vectors.  This is fast but approximate.

A cross-encoder reads the query and document concatenated — it can capture
fine-grained interactions between the two.  Much more accurate for ranking
but too slow to run on all 598 chunks, so we run it only on the top-20
candidates already narrowed down by hybrid search.

Model:     BAAI/bge-reranker-large  (~560 MB, free, local)
Latency:   ~300-500ms for 20 candidates on CPU
"""
from __future__ import annotations
import logging

logger = logging.getLogger("arresto.retrieval.reranker")

_DEFAULT_MODEL = "BAAI/bge-reranker-large"


class Reranker:

    def __init__(self, model_name: str = _DEFAULT_MODEL) -> None:
        self._model_name = model_name
        self._model = None
        self._load()  # eager-load at startup so first request isn't slow

    def _load(self) -> None:
        if self._model is not None:
            return
        try:
            from sentence_transformers import CrossEncoder
        except ImportError as exc:
            raise RuntimeError(
                "Reranker requires 'sentence-transformers'.\n"
                "Install with:  pip install sentence-transformers"
            ) from exc
        logger.info("Loading '%s' ...", self._model_name)
        self._model = CrossEncoder(self._model_name)
        logger.info("Ready.")

    def rerank(
        self,
        query:      str,
        candidates: list[dict],
        top_k:      int = 5,
    ) -> list[dict]:
        """
        Score each (query, chunk_text) pair jointly and return top_k.
        Candidates must be dicts with a 'text' key (from HybridSearcher).
        """
        if not candidates:
            return []
        if len(candidates) <= top_k:
            return candidates

        self._load()

        pairs  = [(query, c["text"]) for c in candidates]
        scores = self._model.predict(pairs)

        ranked = sorted(zip(scores, candidates), key=lambda x: x[0], reverse=True)

        results = []
        for score, chunk in ranked[:top_k]:
            entry = dict(chunk)
            entry["rerank_score"] = round(float(score), 4)
            results.append(entry)

        return results

    @property
    def is_ready(self) -> bool:
        return self._model is not None
