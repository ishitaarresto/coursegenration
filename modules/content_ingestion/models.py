"""
Data models for the content ingestion module.

Pipeline flow:
  Asset -> ExtractedContent (pages/slides/images) -> [Chunk, ...] -> vector DB
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class AssetType(str, Enum):
    PDF  = "pdf"
    DOCX = "docx"
    PPTX = "pptx"


@dataclass
class Asset:
    """Represents a raw uploaded file before extraction."""
    id: str
    file_path: str
    asset_type: AssetType
    original_filename: str
    size_bytes: int
    uploaded_by: str
    course_id: Optional[str] = None
    metadata: dict = field(default_factory=dict)


@dataclass
class ExtractedImage:
    """An image extracted from within a document, with optional BLIP caption."""
    index: int
    image_bytes: bytes
    caption: str = ""
    width: Optional[int] = None
    height: Optional[int] = None
    mime_type: str = ""


@dataclass
class ExtractedPage:
    """A single page extracted from a PDF document."""
    page_number: int
    raw_text: str
    cleaned_text: str = ""
    width: Optional[float] = None
    height: Optional[float] = None
    image_bytes: Optional[bytes] = None
    images: list[ExtractedImage] = field(default_factory=list)
    is_ocr: bool = False     # True when text came from OCR, not embedded PDF text


@dataclass
class ExtractedSlide:
    """A single slide extracted from a PPTX presentation."""
    slide_number: int
    raw_text: str
    speaker_notes: str = ""
    cleaned_text: str = ""
    image_bytes: Optional[bytes] = None
    images: list[ExtractedImage] = field(default_factory=list)


@dataclass
class ExtractedContent:
    """The full result of running an extractor on an Asset."""
    asset: Asset
    full_text: str = ""
    pages: list[ExtractedPage] = field(default_factory=list)
    slides: list[ExtractedSlide] = field(default_factory=list)
    images: list[ExtractedImage] = field(default_factory=list)
    title: str = ""
    author: str = ""
    doc_metadata: dict = field(default_factory=dict)
    extraction_errors: list[str] = field(default_factory=list)
    chunks: list["Chunk"] = field(default_factory=list)


@dataclass
class Chunk:
    """
    A single text unit ready for embedding and vector storage.

    One document produces N chunks. Each chunk carries enough metadata for
    the RAG layer to cite its exact source (file -> page/slide -> heading).
    `embedding` is None until the Embedder runs.
    """
    chunk_id: str
    text: str
    asset_id: str
    source_file: str
    asset_type: str
    chunk_index: int
    token_count: int
    page_number: Optional[int] = None
    slide_number: Optional[int] = None
    section_heading: Optional[str] = None
    is_ocr: bool = False     # True when chunk text was produced by OCR
    embedding: Optional[list[float]] = None
