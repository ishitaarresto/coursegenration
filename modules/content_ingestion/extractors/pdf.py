"""
PDF extractor using PyMuPDF (fitz).

Responsibilities:
- Open the PDF via fitz.open() and iterate over pages
- For each page:
    * Try page.get_text() first (fast path -- works for digital PDFs)
    * If the result is empty/near-empty AND the page has embedded images,
      the page is a scanned image -- render it to PNG and run OCR (slow path)
- Extract embedded images; insert [Image N] placeholders into the text
- Optionally render each page to a PNG thumbnail
- Pull document-level metadata from doc.metadata

OCR is opt-in (enable_ocr=False by default) to keep fast ingestion for
the common case of digital PDFs.
"""

import fitz  # PyMuPDF

from modules.content_ingestion.extractors.base import BaseExtractor
from modules.content_ingestion.models import (
    Asset, AssetType, ExtractedContent, ExtractedImage, ExtractedPage,
)
from modules.content_ingestion.ocr import OCREngine, needs_ocr, OCR_DPI

MIN_IMAGE_DIM = 50  # pixels; images smaller than this are decorative noise


class PdfExtractor(BaseExtractor):
    """Extracts text, embedded images, and optional OCR from PDF files."""

    def __init__(
        self,
        render_images: bool = False,
        image_dpi:     int  = 150,
        enable_ocr:    bool = False,
        ocr_lang:      str  = "eng",
    ) -> None:
        self.render_images = render_images
        self.image_dpi     = image_dpi
        self._ocr          = OCREngine(ocr_lang) if enable_ocr else None

    def can_handle(self, asset: Asset) -> bool:
        return asset.asset_type == AssetType.PDF

    def extract(self, asset: Asset) -> ExtractedContent:
        """
        Extract text (and optionally OCR scanned pages) from a PDF.

        For each page:
          1. page.get_text()  -- instant, works for digital PDFs
          2. If text < 50 chars AND page has images --> OCR path:
               a. Render page to PNG at 300 DPI via PyMuPDF
               b. Pass PNG to OCREngine (Tesseract or EasyOCR)
               c. Use OCR result as the page text
        """
        self._validate_file(asset)
        result = ExtractedContent(asset=asset)

        try:
            doc = fitz.open(asset.file_path)
        except Exception as exc:
            result.extraction_errors.append(f"fitz.open failed: {exc}")
            return result

        meta = doc.metadata or {}
        result.title  = meta.get("title", "")
        result.author = meta.get("author", "")
        result.doc_metadata = {k: v for k, v in meta.items() if v}

        ocr_pages = []   # collect page numbers where OCR was used
        pages = []

        for page_obj in doc:
            text      = page_obj.get_text()
            rect      = page_obj.rect
            raw_images = page_obj.get_images(full=True)

            # -- OCR path: page is a scanned image ----------------------------
            page_is_ocr = False
            if self._ocr and needs_ocr(text, bool(raw_images)):
                # Render at OCR_DPI for best recognition quality
                mat = fitz.Matrix(OCR_DPI / 72, OCR_DPI / 72)
                pix = page_obj.get_pixmap(matrix=mat)
                png = pix.tobytes("png")
                ocr_text = self._ocr.extract_text(png)
                if ocr_text:
                    text = ocr_text          # plain OCR text, no [OCR page N] tag
                    page_is_ocr = True
                    ocr_pages.append(page_obj.number + 1)
                    print(f"[pdf_extractor] Page {page_obj.number + 1}: "
                          f"OCR extracted {len(ocr_text)} chars")

            # -- Embedded image extraction ------------------------------------
            page_images: list[ExtractedImage] = []
            seen_xrefs: set[int] = set()
            img_index = 0

            for img_info in raw_images:
                xref = img_info[0]
                if xref in seen_xrefs:
                    continue
                seen_xrefs.add(xref)
                try:
                    base = doc.extract_image(xref)
                    w, h = base["width"], base["height"]
                    if w < MIN_IMAGE_DIM or h < MIN_IMAGE_DIM:
                        continue
                    page_images.append(ExtractedImage(
                        index=img_index,
                        image_bytes=base["image"],
                        width=w, height=h,
                        mime_type=f"image/{base['ext']}",
                    ))
                    img_index += 1
                except Exception:
                    continue

            if page_images:
                placeholders = "  ".join(
                    f"[Image {img.index}]" for img in page_images
                )
                text = text.rstrip() + f"\n{placeholders}"

            # -- Optional whole-page thumbnail --------------------------------
            thumbnail: bytes | None = None
            if self.render_images:
                mat = fitz.Matrix(self.image_dpi / 72, self.image_dpi / 72)
                pix = page_obj.get_pixmap(matrix=mat)
                thumbnail = pix.tobytes("png")

            pages.append(ExtractedPage(
                page_number=page_obj.number + 1,
                raw_text=text,
                width=rect.width,
                height=rect.height,
                image_bytes=thumbnail,
                images=page_images,
                is_ocr=page_is_ocr,
            ))

        doc.close()
        result.pages     = pages
        result.full_text = "\n".join(p.raw_text for p in pages)
        if ocr_pages:
            result.doc_metadata["ocr_pages"] = ocr_pages
        return result
