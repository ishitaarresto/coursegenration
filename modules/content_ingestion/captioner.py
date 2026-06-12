"""
Image captioner using BLIP-2 (Salesforce/blip2-opt-2.7b, ~6 GB).

BLIP-2 connects a vision encoder to a large language model (OPT-2.7B) via a
lightweight Q-Former bridge.  It reasons about images rather than just
pattern-matching, producing much richer descriptions than BLIP-base:
- Reads text embedded in images (charts with labels, slide titles)
- Describes diagrams and spatial relationships
- Understands context (e.g. "a flowchart showing a 5-step pipeline")

Why not moondream2
------------------
moondream2 uses trust_remote_code=True and downloads custom Python files that
were written for transformers 4.x.  In transformers 5.x, PreTrainedModel gained
a required method `all_tied_weights_keys` that the custom HfMoondream class does
not implement.  Every loading path hits the same crash, regardless of workarounds.
BLIP-2 is a first-class transformers model -- no custom code, no compatibility
issues.

Speed expectations
------------------
CPU : 30-120 s per image (fine for background batch ingest, not real-time)
GPU : 1-3 s per image

Pipeline position:  extract -> caption -> clean
  Replaces every [Image N] placeholder with [Image N: <caption>] so the
  cleaner, chunker, and embedder all see image descriptions as plain text.

Dependencies (in requirements.txt):
    pip install transformers torch
"""

from __future__ import annotations
import logging

logger = logging.getLogger("arresto.captioner")

import io
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from modules.content_ingestion.models import ExtractedContent

_DEFAULT_MODEL = "Salesforce/blip2-opt-2.7b"
_MIN_DIM       = 32   # skip images smaller than this in either dimension


class ImageCaptioner:
    """Lazy-loading BLIP-2 captioner."""

    def __init__(self, model_id: str = _DEFAULT_MODEL, device: str = "auto") -> None:
        self.model_id     = model_id
        self._device_pref = device
        self._model       = None
        self._processor   = None
        self._device: str | None = None

    # -- Model loading ----------------------------------------------------------

    def _load(self) -> None:
        if self._model is not None:
            return
        try:
            import torch
            from transformers import Blip2ForConditionalGeneration, Blip2Processor
        except ImportError as exc:
            raise RuntimeError(
                "Captioning requires 'transformers' and 'torch'.\n"
                "Install with:  pip install transformers torch"
            ) from exc

        device = self._device_pref
        if device == "auto":
            device = "cuda" if torch.cuda.is_available() else "cpu"

        # float16 only on CUDA -- CPU must stay float32
        dtype = torch.float16 if device == "cuda" else torch.float32

        logger.info("Loading '%s' on %s (~6 GB) ...", self.model_id, device)
        logger.info("CPU inference: ~30-120 s per image. GPU: ~1-3 s.")

        self._processor = Blip2Processor.from_pretrained(self.model_id)
        self._model = Blip2ForConditionalGeneration.from_pretrained(
            self.model_id,
            torch_dtype=dtype,
        ).to(device)
        self._model.eval()
        self._device = device
        logger.info("BLIP-2 ready.")

    # -- Single-image caption ---------------------------------------------------

    def caption(self, image_bytes: bytes) -> str:
        """Return a natural-language description for one image (raw bytes).

        Returns "" if the image is unreadable or smaller than _MIN_DIM px.
        """
        self._load()
        import torch
        from PIL import Image

        try:
            img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        except Exception:
            return ""

        if img.width < _MIN_DIM or img.height < _MIN_DIM:
            return ""

        try:
            inputs = self._processor(images=img, return_tensors="pt").to(self._device)
            with torch.no_grad():
                generated_ids = self._model.generate(**inputs, max_new_tokens=60)
            caption = self._processor.batch_decode(
                generated_ids, skip_special_tokens=True
            )[0].strip()
            return caption
        except Exception as exc:
            logger.warning("Caption failed: %s", exc)
            return ""

    # -- Full-content captioning ------------------------------------------------

    def caption_content(self, content: "ExtractedContent") -> "ExtractedContent":
        """Caption every ExtractedImage and inject descriptions into text."""
        if content.pages:
            self._caption_pages(content)
        elif content.slides:
            self._caption_slides(content)
        else:
            self._caption_docx(content)
        return content

    # -- Private helpers --------------------------------------------------------

    def _inject(self, text: str, images: list) -> str:
        for img in images:
            if img.caption:
                text = text.replace(
                    f"[Image {img.index}]",
                    f"[Image {img.index}: {img.caption}]",
                )
        return text

    def _caption_pages(self, content: "ExtractedContent") -> None:
        for page in content.pages:
            if not page.images:
                continue
            logger.info("PDF page %d: %d image(s)", page.page_number, len(page.images))
            for img in page.images:
                img.caption = self.caption(img.image_bytes)
                logger.debug("  image %d -> %s", img.index, img.caption or "(skipped)")
            page.raw_text = self._inject(page.raw_text, page.images)

    def _caption_slides(self, content: "ExtractedContent") -> None:
        for slide in content.slides:
            if not slide.images:
                continue
            logger.info("PPTX slide %d: %d image(s)", slide.slide_number, len(slide.images))
            for img in slide.images:
                img.caption = self.caption(img.image_bytes)
                logger.debug("  image %d -> %s", img.index, img.caption or "(skipped)")
            slide.raw_text = self._inject(slide.raw_text, slide.images)

    def _caption_docx(self, content: "ExtractedContent") -> None:
        if not content.images:
            return
        logger.info("DOCX: %d image(s)", len(content.images))
        for img in content.images:
            img.caption = self.caption(img.image_bytes)
            logger.debug("  image %d -> %s", img.index, img.caption or "(skipped)")
        content.full_text = self._inject(content.full_text, content.images)
