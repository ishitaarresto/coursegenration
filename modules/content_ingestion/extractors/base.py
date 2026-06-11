"""
Abstract base class for all content extractors.

Each extractor (PDF, DOCX, PPTX) must inherit from BaseExtractor and implement:
- `can_handle(asset)` -- returns True if this extractor supports the given AssetType
- `extract(asset)` -- performs extraction and returns an ExtractedContent instance

This base also provides shared utilities like file validation and error accumulation
so subclasses don't repeat boilerplate.
"""

import os
from abc import ABC, abstractmethod
from pathlib import Path

from modules.content_ingestion.models import Asset, ExtractedContent


class BaseExtractor(ABC):
    """Abstract extractor -- subclass for each supported file format."""

    @abstractmethod
    def can_handle(self, asset: Asset) -> bool:
        """Return True if this extractor supports the asset's file type."""
        ...

    @abstractmethod
    def extract(self, asset: Asset) -> ExtractedContent:
        """
        Extract text (and optionally images) from the asset.

        Must return an ExtractedContent even on partial failure;
        append error messages to ExtractedContent.extraction_errors rather
        than raising so the pipeline can continue with degraded output.
        """
        ...

    def _validate_file(self, asset: Asset) -> None:
        """Raise ValueError if the file path is missing or unreadable."""
        path = Path(asset.file_path)
        if not path.exists():
            raise ValueError(f"File not found: {asset.file_path}")
        if not path.is_file():
            raise ValueError(f"Path is not a file: {asset.file_path}")
        if not os.access(asset.file_path, os.R_OK):
            raise ValueError(f"File is not readable: {asset.file_path}")
