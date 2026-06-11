"""
Vector store wrapper around ChromaDB (bge-m3, 1024-dim).

Chunks are stored with their bge-m3 embedding vectors and metadata so
the RAG layer can:
  1. Run semantic similarity search (query_embedding -> top-K chunks)
  2. Filter by source_file, asset_type, page_number, slide_number, etc.
  3. Return chunk text + provenance for answer generation

ChromaDB persists to disk automatically under `persist_dir`.
The collection uses cosine similarity (hnsw:space = "cosine").
Collection name: lms_chunks_bge_m3 (1024-dim; previously lms_chunks at 384-dim).
"""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from modules.content_ingestion.models import Chunk

_COLLECTION = "lms_chunks_bge_m3"


class VectorStore:

    def __init__(self, persist_dir: str = "./chroma_db") -> None:
        try:
            import chromadb
        except ImportError as exc:
            raise RuntimeError(
                "VectorStore requires 'chromadb'.\n"
                "Install with:  pip install chromadb"
            ) from exc

        Path(persist_dir).mkdir(parents=True, exist_ok=True)
        self._client = chromadb.PersistentClient(path=persist_dir)
        self._col = self._client.get_or_create_collection(
            name=_COLLECTION,
            metadata={"hnsw:space": "cosine"},
        )
        print(f"[vector_store] Collection '{_COLLECTION}' ready -- "
              f"{self._col.count()} chunks already stored.")

    def _reconnect(self) -> None:
        """Re-fetch the collection handle when it becomes stale.

        This happens if the collection is deleted and recreated externally
        (e.g. by a migration script) while the server is running. ChromaDB
        collection objects hold an internal UUID that becomes invalid after
        deletion — re-fetching gives us the new UUID.
        """
        self._col = self._client.get_or_create_collection(
            name=_COLLECTION,
            metadata={"hnsw:space": "cosine"},
        )
        print(f"[vector_store] Reconnected to '{_COLLECTION}' "
              f"({self._col.count()} chunks).")

    def _col_op(self, fn):
        """Call fn(col), retrying once after reconnect on NotFoundError."""
        try:
            return fn(self._col)
        except Exception as exc:
            if "does not exist" in str(exc).lower() or "notfound" in type(exc).__name__.lower():
                self._reconnect()
                return fn(self._col)
            raise

    # -- Write ------------------------------------------------------------------

    def upsert(self, chunks: list["Chunk"]) -> None:
        """Insert or update chunks.  Existing chunk_ids are overwritten."""
        if not chunks:
            return
        metadatas = [
            {
                "source_file":     c.source_file,
                "asset_type":      c.asset_type,
                "chunk_index":     c.chunk_index,
                "page_number":     c.page_number  if c.page_number  is not None else -1,
                "slide_number":    c.slide_number if c.slide_number is not None else -1,
                "section_heading": c.section_heading or "",
                "token_count":     c.token_count,
                "is_ocr":          c.is_ocr,
            }
            for c in chunks
        ]
        self._col_op(lambda col: col.upsert(
            ids=[c.chunk_id for c in chunks],
            embeddings=[c.embedding for c in chunks],
            documents=[c.text for c in chunks],
            metadatas=metadatas,
        ))
        print(f"[vector_store] Upserted {len(chunks)} chunks. "
              f"Total in DB: {self.count()}")

    def delete_by_source(self, source_file: str) -> None:
        """Remove all chunks belonging to a given source file."""
        self._col_op(lambda col: col.delete(where={"source_file": source_file}))

    # -- Read -------------------------------------------------------------------

    def query(
        self,
        query_embedding: list[float],
        n_results: int = 5,
        source_file: str | None = None,
        asset_type: str | None = None,
    ) -> list[dict]:
        """
        Return the top-n_results most similar chunks.

        Optional filters:
          source_file  - restrict to one document
          asset_type   - restrict to "pdf", "docx", or "pptx"
        """
        where: dict | None = None
        if source_file and asset_type:
            where = {"$and": [{"source_file": source_file},
                               {"asset_type": asset_type}]}
        elif source_file:
            where = {"source_file": source_file}
        elif asset_type:
            where = {"asset_type": asset_type}

        n = min(n_results, self.count())
        if n == 0:
            return []

        results = self._col_op(lambda col: col.query(
            query_embeddings=[query_embedding],
            n_results=n,
            where=where,
            include=["documents", "metadatas", "distances"],
        ))

        return [
            {
                "chunk_id":  results["ids"][0][i],
                "text":      results["documents"][0][i],
                "metadata":  results["metadatas"][0][i],
                "score":     round(1 - results["distances"][0][i], 4),
            }
            for i in range(len(results["ids"][0]))
        ]

    def get_all_by_source(self, source_file: str) -> list[dict]:
        """Return every chunk stored for a given source file, ordered by chunk_index."""
        results = self._col_op(lambda col: col.get(
            where={"source_file": source_file},
            include=["documents", "metadatas"],
        ))
        rows = [
            {
                "chunk_id": results["ids"][i],
                "text":     results["documents"][i],
                "metadata": results["metadatas"][i],
            }
            for i in range(len(results["ids"]))
        ]
        rows.sort(key=lambda r: r["metadata"].get("chunk_index", 0))
        return rows

    def list_sources(self) -> list[str]:
        """Return unique source_file values across all stored chunks."""
        if self.count() == 0:
            return []
        results = self._col_op(lambda col: col.get(include=["metadatas"]))
        seen: set[str] = set()
        sources: list[str] = []
        for m in results["metadatas"]:
            sf = m.get("source_file", "")
            if sf and sf not in seen:
                seen.add(sf)
                sources.append(sf)
        return sorted(sources)

    def count(self) -> int:
        return self._col_op(lambda col: col.count())
