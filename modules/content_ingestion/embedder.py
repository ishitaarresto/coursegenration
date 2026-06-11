"""
Text embedder using sentence-transformers (BAAI/bge-m3).

bge-m3 produces 1024-dimensional vectors and supports 100+ languages,
making it suitable for multilingual safety training content.
The model (~570 MB) is downloaded once and cached by sentence-transformers.

Previously used all-MiniLM-L6-v2 (384-dim, English-only).
Switching to bge-m3 aligns the ingestion embeddings with the retrieval
pipeline so both RAG chat and the AI tutor operate in the same vector space.

NOTE: existing ChromaDB data embedded with MiniLM must be re-ingested —
the vector dimension changed from 384 to 1024.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from modules.content_ingestion.models import Chunk

_DEFAULT_MODEL = "BAAI/bge-m3"


class Embedder:
    """Lazy-loading sentence-transformer embedder."""

    def __init__(self, model_name: str = _DEFAULT_MODEL) -> None:
        self.model_name = model_name
        self._model = None

    def _load(self) -> None:
        if self._model is not None:
            return
        try:
            from sentence_transformers import SentenceTransformer
        except ImportError as exc:
            raise RuntimeError(
                "Embedding requires 'sentence-transformers'.\n"
                "Install with:  pip install sentence-transformers"
            ) from exc
        print(f"[embedder] Loading '{self.model_name}' ...")
        self._model = SentenceTransformer(self.model_name)
        dim = self._model.get_sentence_embedding_dimension()
        print(f"[embedder] Ready -- embedding dimension: {dim}")

    @property
    def dimension(self) -> int:
        self._load()
        return self._model.get_sentence_embedding_dimension()

    def embed_texts(self, texts: list[str]) -> list[list[float]]:
        """Embed a list of strings; returns a parallel list of float vectors."""
        self._load()
        vectors = self._model.encode(
            texts,
            show_progress_bar=True,
            convert_to_numpy=True,
            batch_size=32,
        )
        return vectors.tolist()

    def embed_query(self, text: str) -> list[float]:
        """Embed a single query string (no progress bar)."""
        self._load()
        return self._model.encode(text, convert_to_numpy=True).tolist()

    def embed_chunks(self, chunks: list["Chunk"]) -> list["Chunk"]:
        """Embed every chunk in place; returns the same list with .embedding set."""
        if not chunks:
            return chunks
        print(f"[embedder] Embedding {len(chunks)} chunks ...")
        vectors = self.embed_texts([c.text for c in chunks])
        for chunk, vec in zip(chunks, vectors):
            chunk.embedding = vec
        print(f"[embedder] Done.")
        return chunks
