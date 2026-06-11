"""
Extractor sub-package for content_ingestion.

Exports the concrete extractor classes so the pipeline can import from a single
location rather than knowing each module path:

    from modules.content_ingestion.extractors import PdfExtractor, DocxExtractor, PptxExtractor
"""

from modules.content_ingestion.extractors.pdf import PdfExtractor
from modules.content_ingestion.extractors.docx import DocxExtractor
from modules.content_ingestion.extractors.pptx import PptxExtractor

__all__ = ["PdfExtractor", "DocxExtractor", "PptxExtractor"]
