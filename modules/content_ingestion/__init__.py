"""
content_ingestion -- Arresto LMS module.

Handles the full lifecycle of importing educational content files (PDF, DOCX, PPTX)
into the platform: file validation, text extraction, normalization, and preparation
for downstream chunking and embedding.

Public API:
    IngestionPipeline -- the main entry point; call pipeline.run(asset) to ingest a file
    Asset, AssetType  -- domain models for representing an uploaded file
    ExtractedContent  -- the result type returned by the pipeline

Usage:
    from modules.content_ingestion import IngestionPipeline
    from modules.content_ingestion.models import Asset, AssetType

    pipeline = IngestionPipeline()
    content = pipeline.run(asset)
"""

from modules.content_ingestion.pipeline import IngestionPipeline, UnsupportedAssetTypeError
from modules.content_ingestion.models import Asset, AssetType, ExtractedContent

__all__ = [
    "IngestionPipeline",
    "UnsupportedAssetTypeError",
    "Asset",
    "AssetType",
    "ExtractedContent",
]
