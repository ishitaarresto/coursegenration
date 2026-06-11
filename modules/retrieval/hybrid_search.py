"""
modules/retrieval/hybrid_search.py -- Dense + Sparse retrieval fused with RRF.

Reciprocal Rank Fusion formula:
    score(d) = sum_i( 1 / (k + rank_i(d)) )

  k = 60  (constant — dampens impact of very high-ranked documents, prevents
           one signal from completely dominating the other)

Dense retrieval: bge-m3 embeddings in ChromaDB (cross-lingual, semantic)
Sparse retrieval: BM25 keyword matching (exact terms, abbreviations, codes)

The combined top-20 candidates are passed to the Reranker.
"""
from __future__ import annotations

from typing import Callable, TYPE_CHECKING

if TYPE_CHECKING:
    from modules.retrieval.bge_store  import BGEVectorStore
    from modules.retrieval.bm25_index import BM25Index

_RRF_K = 60


def _rrf_fuse(rankings: list[list[str]], k: int = _RRF_K) -> dict[str, float]:
    scores: dict[str, float] = {}
    for ranking in rankings:
        for rank, chunk_id in enumerate(ranking):
            scores[chunk_id] = scores.get(chunk_id, 0.0) + 1.0 / (k + rank + 1)
    return scores


class HybridSearcher:

    def __init__(
        self,
        bge_store:  "BGEVectorStore",
        bm25_index: "BM25Index",
        embed_fn:   Callable[[str], list[float]],
    ) -> None:
        self._store    = bge_store
        self._bm25     = bm25_index
        self._embed_fn = embed_fn   # str -> list[float]

    def search(
        self,
        query:       str,
        n_results:   int = 20,
        source_file: str | None = None,
    ) -> list[dict]:
        """
        Return top-n candidates fused from dense (bge-m3) + sparse (BM25) search,
        ranked by Reciprocal Rank Fusion score.
        """
        # 1. Dense retrieval
        q_vec     = self._embed_fn(query)
        dense     = self._store.query(q_vec, n_results=n_results, source_file=source_file)
        dense_ids = [h["chunk_id"] for h in dense]

        # 2. Sparse retrieval
        sparse     = self._bm25.search(query, n_results=n_results, source_file=source_file)
        sparse_ids = [h["chunk_id"] for h in sparse]

        # 3. RRF fusion — order matters; both lists have equal weight
        fused = _rrf_fuse([dense_ids, sparse_ids])

        # 4. Build chunk map from both result sets (dense has cosine score; sparse has BM25)
        chunk_map: dict[str, dict] = {}
        for h in dense:
            chunk_map[h["chunk_id"]] = h
        for h in sparse:
            if h["chunk_id"] not in chunk_map:
                chunk_map[h["chunk_id"]] = h

        # 5. Sort by RRF score, cap at n_results
        ranked = sorted(fused.items(), key=lambda x: x[1], reverse=True)
        results = []
        for chunk_id, rrf_score in ranked[:n_results]:
            if chunk_id in chunk_map:
                entry = dict(chunk_map[chunk_id])
                entry["rrf_score"] = round(rrf_score, 6)
                results.append(entry)

        return results
