"""
modules/retrieval/bm25_index.py -- Sparse keyword retrieval (BM25).

Dense embeddings blur over exact technical terms — "600V", "LOTO", specific
regulation codes.  BM25 does exact token matching, so when a learner types
those exact terms they always rank high in the sparse results.

Combined with dense retrieval and RRF fusion in hybrid_search.py, this
significantly improves recall for technical queries without slowing things down.

Requires:  pip install rank-bm25
"""
from __future__ import annotations

import re


def _tokenize(text: str) -> list[str]:
    """Lowercase word tokenisation. Keeps digits ('600v' stays as '600v')."""
    return re.findall(r"\b\w+\b", text.lower())


class BM25Index:

    def __init__(self) -> None:
        self._corpus_ids:   list[str]  = []
        self._corpus_meta:  list[dict] = []
        self._corpus_texts: list[str]  = []
        self._bm25 = None

    def build(self, chunks: list[dict]) -> None:
        """Build index from a list of {chunk_id, text, metadata} dicts."""
        try:
            from rank_bm25 import BM25Okapi
        except ImportError as exc:
            raise RuntimeError(
                "BM25 requires 'rank-bm25'.\n"
                "Install with:  pip install rank-bm25"
            ) from exc

        self._corpus_ids   = [c["chunk_id"] for c in chunks]
        self._corpus_meta  = [c["metadata"]  for c in chunks]
        self._corpus_texts = [c["text"]       for c in chunks]
        tokenized          = [_tokenize(t) for t in self._corpus_texts]
        self._bm25         = BM25Okapi(tokenized)
        print(f"[bm25] Index built — {len(self._corpus_ids)} documents.")

    def search(
        self,
        query: str,
        n_results: int = 20,
        source_file: str | None = None,
    ) -> list[dict]:
        """Return top-n chunks ranked by BM25 score, optionally filtered."""
        if self._bm25 is None:
            return []

        tokens = _tokenize(query)
        scores = self._bm25.get_scores(tokens)

        ranked = sorted(enumerate(scores), key=lambda x: x[1], reverse=True)

        results = []
        for idx, score in ranked:
            if score <= 0:
                continue
            meta = self._corpus_meta[idx]
            if source_file and meta.get("source_file") != source_file:
                continue
            results.append({
                "chunk_id": self._corpus_ids[idx],
                "text":     self._corpus_texts[idx],
                "metadata": meta,
                "score":    float(score),
            })
            if len(results) >= n_results:
                break

        return results

    @property
    def is_ready(self) -> bool:
        return self._bm25 is not None
