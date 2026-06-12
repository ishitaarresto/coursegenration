"""
modules/retrieval/bge_store.py -- ChromaDB wrapper for the bge-m3 collection.

The collection was built by compare_retrieval.py and lives in a separate
directory so the original MiniLM collection is untouched.  This store is used
exclusively by the intelligent retrieval pipeline; the ingestion pipeline still
writes to the MiniLM collection (chroma_db/).

When new documents are uploaded they will need to be dual-indexed here too —
that wiring comes later in the ingestion pipeline.
"""
from __future__ import annotations
import logging

logger = logging.getLogger("arresto.retrieval.bge")

from pathlib import Path

_COLLECTION = "lms_chunks_bge_m3"


class BGEVectorStore:
    """Thin ChromaDB wrapper for the bge-m3 multilingual collection."""

    def __init__(self, persist_dir: str = "./chroma_db_bge_comparison") -> None:
        import chromadb
        Path(persist_dir).mkdir(parents=True, exist_ok=True)
        self._client = chromadb.PersistentClient(path=persist_dir)
        self._col = self._client.get_or_create_collection(
            name=_COLLECTION,
            metadata={"hnsw:space": "cosine"},
        )
        logger.info("'%s' ready — %d chunks.", _COLLECTION, self._col.count())

    def query(
        self,
        query_embedding: list[float],
        n_results: int = 20,
        source_file: str | None = None,
    ) -> list[dict]:
        where = {"source_file": source_file} if source_file else None
        n = min(n_results, max(self._col.count(), 1))
        results = self._col.query(
            query_embeddings=[query_embedding],
            n_results=n,
            where=where,
            include=["documents", "metadatas", "distances"],
        )
        return [
            {
                "chunk_id": results["ids"][0][i],
                "text":     results["documents"][0][i],
                "metadata": results["metadatas"][0][i],
                "score":    round(1 - results["distances"][0][i], 4),
            }
            for i in range(len(results["ids"][0]))
        ]

    def get_all(self) -> list[dict]:
        """Return every chunk — consumed once at startup to build the BM25 index."""
        results = self._col.get(include=["documents", "metadatas"])
        return [
            {
                "chunk_id": results["ids"][i],
                "text":     results["documents"][i],
                "metadata": results["metadatas"][i],
            }
            for i in range(len(results["ids"]))
        ]

    def upsert(
        self,
        ids:        list[str],
        embeddings: list[list[float]],
        documents:  list[str],
        metadatas:  list[dict],
    ) -> None:
        self._col.upsert(
            ids=ids, embeddings=embeddings,
            documents=documents, metadatas=metadatas,
        )

    def delete_by_source(self, source_file: str) -> None:
        """Remove all chunks belonging to a given source file."""
        self._col.delete(where={"source_file": source_file})

    def count(self) -> int:
        return self._col.count()
