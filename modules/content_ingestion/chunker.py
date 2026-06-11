"""
Text chunker -- splits ExtractedContent into Chunk objects for embedding.

Strategy per format
-------------------
DOCX  Heading-aware split.  The # / ## markers written by the DOCX extractor
      are the natural section boundaries.  H1 sections are primary chunks;
      sections that exceed max_tokens are split further on H2, then on
      individual paragraphs with a sliding overlap window.

PDF   Page-based.  Each page is one chunk.  Pages that exceed max_tokens are
      split on paragraph boundaries with overlap.

PPTX  Slide-based.  Each slide is one chunk (slides are rarely longer than
      max_tokens).  Speaker notes, when present, are appended to the slide
      chunk so the full slide context travels together.

Token counting
--------------
We use word count as a fast approximation (1 word ~= 1.3 BPE tokens).
max_tokens=400 words ~= 500-520 BPE tokens, well within the 512-token
context window of MiniLM and similar sentence-transformer models.
"""

import re
from dataclasses import dataclass

from modules.content_ingestion.models import Chunk, ExtractedContent


@dataclass
class ChunkingConfig:
    max_tokens: int   = 400   # max words per chunk
    overlap_tokens: int = 50  # overlap words carried into the next chunk
    min_tokens: int   = 20    # discard chunks shorter than this


# -- Helpers --------------------------------------------------------------------

def _wc(text: str) -> int:
    return len(text.split())


def _slug(filename: str) -> str:
    """Filesystem-safe prefix for chunk IDs derived from the filename."""
    return re.sub(r"[^a-z0-9]+", "_", filename.lower())[:40].strip("_")


def _split_paragraphs_with_overlap(
    paragraphs: list[str],
    max_tokens: int,
    overlap_tokens: int,
    min_tokens: int,
) -> list[str]:
    """
    Greedily pack paragraphs into chunks up to max_tokens words.
    When a chunk is full, carry the last `overlap_tokens` words worth of
    paragraphs into the next chunk so context is not lost at boundaries.
    """
    chunks: list[str] = []
    window: list[str] = []
    window_wc = 0

    for para in paragraphs:
        para_wc = _wc(para)
        if window_wc + para_wc > max_tokens and window:
            text = "\n".join(window).strip()
            if _wc(text) >= min_tokens:
                chunks.append(text)
            # Build overlap tail
            overlap: list[str] = []
            overlap_wc = 0
            for p in reversed(window):
                w = _wc(p)
                if overlap_wc + w <= overlap_tokens:
                    overlap.insert(0, p)
                    overlap_wc += w
                else:
                    break
            window = overlap + [para]
            window_wc = overlap_wc + para_wc
        else:
            window.append(para)
            window_wc += para_wc

    if window:
        text = "\n".join(window).strip()
        if _wc(text) >= min_tokens:
            chunks.append(text)

    return chunks


# -- Main class -----------------------------------------------------------------

class Chunker:

    def __init__(self, config: ChunkingConfig | None = None) -> None:
        self.cfg = config or ChunkingConfig()

    def chunk(self, content: ExtractedContent) -> list[Chunk]:
        if content.pages:
            return self._chunk_pdf(content)
        if content.slides:
            return self._chunk_pptx(content)
        return self._chunk_docx(content)

    # -- Private builders -------------------------------------------------------

    def _make(
        self,
        text: str,
        content: ExtractedContent,
        idx: int,
        *,
        page: int | None = None,
        slide: int | None = None,
        heading: str | None = None,
        is_ocr: bool = False,
    ) -> Chunk:
        prefix = _slug(content.asset.original_filename)
        return Chunk(
            chunk_id=f"{prefix}_{idx:04d}",
            text=text,
            asset_id=content.asset.id,
            source_file=content.asset.original_filename,
            asset_type=content.asset.asset_type.value,
            chunk_index=idx,
            token_count=_wc(text),
            page_number=page,
            slide_number=slide,
            section_heading=heading,
            is_ocr=is_ocr,
        )

    def _chunk_pdf(self, content: ExtractedContent) -> list[Chunk]:
        chunks: list[Chunk] = []
        idx = 0
        for page in content.pages:
            text = page.cleaned_text.strip()
            if not text:
                continue

            # For OCR pages the "heading" is page N (the [OCR page N] tag is gone
            # so we synthesise a heading from the page number instead).
            # For digital pages the first non-empty line is a good heading.
            if page.is_ocr:
                heading = f"Page {page.page_number} (OCR)"
            else:
                heading = next((l.strip() for l in text.splitlines() if l.strip()), None)

            if _wc(text) <= self.cfg.max_tokens:
                chunks.append(self._make(text, content, idx,
                                         page=page.page_number,
                                         heading=heading,
                                         is_ocr=page.is_ocr))
                idx += 1
            else:
                paras = [p for p in text.splitlines() if p.strip()]
                for sub in _split_paragraphs_with_overlap(
                        paras, self.cfg.max_tokens,
                        self.cfg.overlap_tokens, self.cfg.min_tokens):
                    chunks.append(self._make(sub, content, idx,
                                             page=page.page_number,
                                             heading=heading,
                                             is_ocr=page.is_ocr))
                    idx += 1
        return chunks

    def _chunk_pptx(self, content: ExtractedContent) -> list[Chunk]:
        chunks: list[Chunk] = []
        idx = 0
        for slide in content.slides:
            text = slide.cleaned_text.strip()
            if not text:
                continue
            if slide.speaker_notes:
                text = text + "\n[Notes] " + slide.speaker_notes.strip()
            heading = next((l.strip() for l in text.splitlines() if l.strip()), None)
            if _wc(text) <= self.cfg.max_tokens:
                chunks.append(self._make(text, content, idx,
                                         slide=slide.slide_number, heading=heading))
                idx += 1
            else:
                paras = [p for p in text.splitlines() if p.strip()]
                for sub in _split_paragraphs_with_overlap(
                        paras, self.cfg.max_tokens,
                        self.cfg.overlap_tokens, self.cfg.min_tokens):
                    chunks.append(self._make(sub, content, idx,
                                             slide=slide.slide_number, heading=heading))
                    idx += 1
        return chunks

    def _chunk_docx(self, content: ExtractedContent) -> list[Chunk]:
        """
        Split on # (H1) first -> each H1 section becomes one or more chunks.
        Sections longer than max_tokens are split further on ## (H2) sections,
        then on paragraph boundaries with overlap if still too long.
        """
        chunks: list[Chunk] = []
        idx = 0

        # Split text into H1 blocks (each starts with "# " or is pre-heading text)
        h1_blocks = re.split(r"(?m)^(?=# )", content.full_text)

        for block in h1_blocks:
            block = block.strip()
            if not block:
                continue

            first_line = block.splitlines()[0].strip()
            h1_heading = first_line.lstrip("#").strip() if first_line.startswith("#") else None

            if _wc(block) <= self.cfg.max_tokens:
                chunks.append(self._make(block, content, idx, heading=h1_heading))
                idx += 1
                continue

            # Block is too long -> split on ## (H2)
            h2_blocks = re.split(r"(?m)^(?=## )", block)
            for sub in h2_blocks:
                sub = sub.strip()
                if not sub:
                    continue
                sub_first = sub.splitlines()[0].strip()
                h2_heading = sub_first.lstrip("#").strip() if sub_first.startswith("#") else h1_heading

                if _wc(sub) <= self.cfg.max_tokens:
                    chunks.append(self._make(sub, content, idx, heading=h2_heading))
                    idx += 1
                    continue

                # Still too long -> paragraph overlap split
                paras = [p for p in sub.splitlines() if p.strip()]
                for piece in _split_paragraphs_with_overlap(
                        paras, self.cfg.max_tokens,
                        self.cfg.overlap_tokens, self.cfg.min_tokens):
                    chunks.append(self._make(piece, content, idx, heading=h2_heading))
                    idx += 1

        return chunks
