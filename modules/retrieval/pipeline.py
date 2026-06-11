"""
modules/retrieval/pipeline.py -- Full intelligent retrieval pipeline (Phases 1-5).

Orchestration order per query:
  Phase 1 — bge-m3 multilingual embeddings (cross-lingual semantic search)
  Phase 4 — Intent detection + query rewriting (Claude Haiku, one call)
  Phase 5 — Contextual rewrite for conversational follow-ups (Claude Haiku, conditional)
  Phase 2 — Hybrid search: Dense (bge-m3 ChromaDB) + Sparse (BM25) + RRF fusion
  Phase 3 — Cross-encoder reranking: top-20 candidates -> top-5 final chunks

Phases are numbered by the implementation order from the architecture doc;
they execute in a different order at query time because intent detection
must happen before retrieval.

Usage:
    pipeline = RetrievalPipeline(api_key=..., bge_db_dir="./chroma_db_bge_comparison")
    result = pipeline.retrieve(query, source_file="doc.pdf", history=[...])
    # result.intent, result.language, result.chunks (list of top-5 dicts)
"""
from __future__ import annotations

from dataclasses import dataclass, field

from modules.retrieval.bge_store       import BGEVectorStore
from modules.retrieval.bm25_index      import BM25Index
from modules.retrieval.hybrid_search   import HybridSearcher
from modules.retrieval.reranker        import Reranker
from modules.retrieval.query_processor import (
    QueryProcessor,
    INTENT_FACTUAL, INTENT_PROCEDURAL, INTENT_CONVERSATIONAL,
    INTENT_SUMMARY, INTENT_QUIZ,
)

_SKIP_RETRIEVAL = {INTENT_SUMMARY, INTENT_QUIZ}


@dataclass
class RetrievalResult:
    intent:      str
    language:    str
    clean_query: str
    final_query: str
    chunks:      list[dict] = field(default_factory=list)
    skipped:     bool = False


class RetrievalPipeline:

    def __init__(
        self,
        api_key:          str,
        bge_db_dir:       str  = "./chroma_db_bge_comparison",
        enable_reranking: bool = True,
        haiku_model:      str  = "claude-haiku-4-5-20251001",
        top_candidates:   int  = 20,
        top_final:        int  = 5,
    ) -> None:
        self._top_candidates   = top_candidates
        self._top_final        = top_final
        self._enable_reranking = enable_reranking

        # Phase 1 — bge-m3 vector store
        print("[retrieval] Opening bge-m3 ChromaDB ...")
        self._bge_store = BGEVectorStore(persist_dir=bge_db_dir)

        # Phase 1 — bge-m3 embedding model
        print("[retrieval] Loading bge-m3 (cached after first download) ...")
        from sentence_transformers import SentenceTransformer
        self._st_model = SentenceTransformer("BAAI/bge-m3")
        dim = self._st_model.get_sentence_embedding_dimension()
        print(f"[retrieval] bge-m3 ready — dim={dim}")

        # Phase 2 — BM25 sparse index (built once from all stored chunks)
        print("[retrieval] Building BM25 index ...")
        self._bm25 = BM25Index()
        all_chunks = self._bge_store.get_all()
        self._bm25.build(all_chunks)

        # Phase 2 — Hybrid searcher (dense + sparse + RRF)
        self._searcher = HybridSearcher(
            bge_store=self._bge_store,
            bm25_index=self._bm25,
            embed_fn=self._embed_query,
        )

        # Phase 3 — Cross-encoder reranker (lazy load on first use)
        self._reranker = Reranker() if enable_reranking else None

        # Phases 4 & 5 — Query processor (intent + rewriting via Claude Haiku)
        print("[retrieval] Query processor ready (Claude Haiku).")
        self._processor = QueryProcessor(api_key=api_key, model=haiku_model)

        print(f"[retrieval] Pipeline ready — {self._bge_store.count()} chunks indexed.")

    # -- Internal embed helper passed to HybridSearcher --------------------------

    def _embed_query(self, text: str) -> list[float]:
        return self._st_model.encode(text, convert_to_numpy=True).tolist()

    # -- Dual-index helpers (called by ingestion pipeline on upload/delete) ------

    def dual_index(self, chunks: list) -> None:
        """
        Embed new chunks with bge-m3 and upsert into the BGE store,
        then rebuild the in-memory BM25 index from the full corpus.

        Called automatically by the ingestion pipeline after every successful
        document upload so the retrieval pipeline always sees the latest data.

        chunks: list of Chunk dataclass objects (from content_ingestion.models)
        """
        if not chunks:
            return

        print(f"[retrieval] Dual-indexing {len(chunks)} chunks into bge-m3 store ...")
        texts      = [c.text for c in chunks]
        embeddings = self._st_model.encode(
            texts, convert_to_numpy=True, show_progress_bar=False, batch_size=32,
        ).tolist()

        self._bge_store.upsert(
            ids=[c.chunk_id for c in chunks],
            embeddings=embeddings,
            documents=texts,
            metadatas=[
                {
                    "source_file":     c.source_file,
                    "asset_type":      c.asset_type,
                    "chunk_index":     c.chunk_index,
                    "page_number":     c.page_number  if c.page_number  is not None else -1,
                    "slide_number":    c.slide_number if c.slide_number is not None else -1,
                    "section_heading": c.section_heading or "",
                    "token_count":     c.token_count,
                }
                for c in chunks
            ],
        )

        # BM25 is an in-memory index — rebuild from the full corpus so it
        # stays in sync with every chunk now in the BGE store.
        all_chunks = self._bge_store.get_all()
        self._bm25.build(all_chunks)
        print(f"[retrieval] Dual-index done. BGE store: {self._bge_store.count()} chunks, "
              f"BM25: {len(all_chunks)} docs.")

    def delete_source(self, source_file: str) -> None:
        """
        Remove a source file from the BGE store and rebuild BM25.
        Called when a document is deleted via the API.
        """
        self._bge_store.delete_by_source(source_file)
        all_chunks = self._bge_store.get_all()
        self._bm25.build(all_chunks)
        print(f"[retrieval] '{source_file}' removed from BGE store. "
              f"BM25 rebuilt — {len(all_chunks)} chunks remain.")

    # -- Public API ---------------------------------------------------------------

    def retrieve(
        self,
        query:       str,
        source_file: str | None = None,
        history:     list[dict] | None = None,
    ) -> RetrievalResult:
        """
        Run the full pipeline for a single query.

        Returns a RetrievalResult with:
          .intent      — detected intent
          .language    — detected language (ISO 639-1)
          .clean_query — ASR-cleaned query (same language, no filler words)
          .final_query — after contextual rewrite (may equal clean_query)
          .chunks      — top-5 re-ranked chunks ready for Claude context
          .skipped     — True when intent bypasses retrieval (summary/quiz)
        """
        history = history or []

        # Phase 4 — intent detection + query rewriting
        processed   = self._processor.process(query)
        intent      = processed["intent"]
        language    = processed["language"]
        clean_query = processed["clean_query"]

        # summary / quiz skip retrieval — the answer comes from course script
        if intent in _SKIP_RETRIEVAL:
            return RetrievalResult(
                intent=intent, language=language,
                clean_query=clean_query, final_query=clean_query,
                chunks=[], skipped=True,
            )

        # Phase 5 — contextual rewrite for pronoun-heavy follow-ups
        if intent == INTENT_CONVERSATIONAL and history:
            final_query = self._processor.contextual_rewrite(clean_query, history)
        else:
            final_query = clean_query

        # Phase 2 — hybrid search (dense bge-m3 + BM25 + RRF)
        candidates = self._searcher.search(
            final_query,
            n_results=self._top_candidates,
            source_file=source_file,
        )

        # Phase 3 — cross-encoder reranking (top-20 -> top-5)
        if self._reranker and candidates:
            chunks = self._reranker.rerank(final_query, candidates, top_k=self._top_final)
        else:
            chunks = candidates[:self._top_final]

        return RetrievalResult(
            intent=intent, language=language,
            clean_query=clean_query, final_query=final_query,
            chunks=chunks, skipped=False,
        )
