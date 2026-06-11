"""
Ingestion pipeline orchestrator.

Full pipeline sequence
----------------------
1. Route    -- pick extractor by asset_type
2. Extract  -- raw text + [Image N] placeholders + ExtractedImage objects
3. Caption  -- (optional) BLIP replaces [Image N] with real descriptions
4. Clean    -- unicode / ligature / whitespace normalisation
5. Chunk    -- split cleaned text into Chunk objects with provenance metadata
6. Embed    -- encode each chunk into a float vector via sentence-transformers
7. Store    -- upsert (chunk_id, vector, text, metadata) into ChromaDB
8. Return   -- ExtractedContent with .chunks populated

Every step after Extract is optional; pass None to skip it.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from modules.content_ingestion import cleaner
from modules.content_ingestion.extractors import DocxExtractor, PdfExtractor, PptxExtractor
from modules.content_ingestion.models import Asset, ExtractedContent

if TYPE_CHECKING:
    from modules.content_ingestion.captioner    import ImageCaptioner
    from modules.content_ingestion.chunker      import Chunker
    from modules.content_ingestion.embedder     import Embedder
    from modules.content_ingestion.vector_store import VectorStore


class UnsupportedAssetTypeError(Exception):
    """Raised when no registered extractor can handle the asset's file type."""


class IngestionPipeline:

    def __init__(
        self,
        render_pdf_images: bool = False,
        extract_images:    bool = False,
        enable_ocr:        bool = False,
        ocr_lang:          str  = "eng",
        captioner:    "ImageCaptioner | None" = None,
        chunker:      "Chunker      | None" = None,
        embedder:     "Embedder     | None" = None,
        vector_store: "VectorStore  | None" = None,
    ) -> None:
        _extract = extract_images or (captioner is not None)
        self._extractors = [
            PdfExtractor(render_images=render_pdf_images,
                         enable_ocr=enable_ocr, ocr_lang=ocr_lang),
            DocxExtractor(extract_images=_extract),
            PptxExtractor(extract_images=_extract),
        ]
        self._captioner    = captioner
        self._chunker      = chunker
        self._embedder     = embedder
        self._vector_store = vector_store

    def run(self, asset: Asset) -> ExtractedContent:
        # -- 1-2  Extract ------------------------------------------------------
        content = self._route(asset).extract(asset)

        # -- 3  Caption --------------------------------------------------------
        if self._captioner is not None:
            content = self._captioner.caption_content(content)

        # -- 4  Clean ----------------------------------------------------------
        content = cleaner.clean(content)

        # -- 5  Chunk ----------------------------------------------------------
        if self._chunker is not None:
            chunks = self._chunker.chunk(content)
            print(f"[pipeline] {asset.original_filename} -> {len(chunks)} chunks")

            # -- 6  Embed ------------------------------------------------------
            if self._embedder is not None:
                chunks = self._embedder.embed_chunks(chunks)

            # -- 7  Store ------------------------------------------------------
            if self._vector_store is not None and self._embedder is not None:
                self._vector_store.upsert(chunks)

            content.chunks = chunks

        return content

    def _route(self, asset: Asset):
        for ex in self._extractors:
            if ex.can_handle(asset):
                return ex
        raise UnsupportedAssetTypeError(
            f"No extractor for asset type '{asset.asset_type}'"
        )
