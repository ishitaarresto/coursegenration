"""
OCR engine for scanned PDF pages.

WHY THIS EXISTS
---------------
A PDF can contain two completely different kinds of content:

  Digital PDF  -- created by Word / PowerPoint / any modern tool.
                  Text is stored as characters in the PDF file.
                  PyMuPDF's page.get_text() returns it instantly.

  Scanned PDF  -- printed paper was scanned and saved as PDF.
                  Every page is just a raster image (pixels).
                  page.get_text() returns an empty string.
                  The only way to read the text is OCR.

Company safety manuals and older training documents are very often scanned
PDFs. Without OCR they would ingest as empty documents and be useless for RAG.

HOW DETECTION WORKS
--------------------
After page.get_text() runs, we check two conditions:
  1. Extracted text length < MIN_TEXT_CHARS (the page has almost no digital text)
  2. The page contains at least one embedded image (it is an image, not blank)

If both are true the page is treated as scanned and OCR is triggered.

HOW OCR WORKS
--------------
1. PyMuPDF renders the page to a PNG at OCR_DPI (300 by default).
   Higher DPI = more pixels = better character recognition.
   150 DPI gives roughly 72 pt * 2 = 1190x1684 px. Too low.
   300 DPI gives 2480x3508 px -- equivalent to a proper document scan.

2. The PNG bytes are handed to the OCR engine which:
      a. Detects text regions (bounding boxes)
      b. Segments each region into lines and words
      c. Classifies each character using a neural network or pattern matching
      d. Returns the recognised text as a UTF-8 string

3. The OCR text replaces the empty page.get_text() result and flows into
   the same cleaning -> chunking -> embedding pipeline as digital text.

ENGINE SELECTION
----------------
The class tries engines in this order, using the first one available:

  Tesseract   Industry-standard OCR. Originally HP, now maintained by Google.
              Uses LSTM neural networks. 95-99% accuracy on clean scans.
              REQUIRES a system binary + pytesseract wrapper.
              Install:
                Windows: https://github.com/UB-Mannheim/tesseract/wiki
                then:    pip install pytesseract

  EasyOCR     Pure Python, no binary needed. 80+ languages.
              Downloads ~200 MB ML models on first use.
              Install:   pip install easyocr

  Neither     Raises RuntimeError with install instructions.

ACCURACY NOTES
--------------
  - Clean, straight scans at >= 300 DPI: 95-99% accuracy
  - Slightly rotated or skewed pages: 85-95%
  - Low-quality or blurry scans: <80% -- consider requesting a better scan
  - Handwriting: not supported by default Tesseract/EasyOCR models
  - Tables: text is extracted but grid structure is lost
"""

from __future__ import annotations

import io

MIN_TEXT_CHARS = 50    # pages with fewer chars are assumed scanned
OCR_DPI        = 300   # render DPI for OCR -- higher = better accuracy, more RAM


# -- Detection ----------------------------------------------------------------

def needs_ocr(page_text: str, has_images: bool) -> bool:
    """
    Return True if a PDF page looks like a scanned image rather than
    digital text and OCR should be attempted.
    """
    return len(page_text.strip()) < MIN_TEXT_CHARS and has_images


# -- Engine -------------------------------------------------------------------

class OCREngine:
    """
    Lazy-loading OCR engine. Detects and uses the first available backend
    (Tesseract, then EasyOCR) on the first call to extract_text().
    """

    # EasyOCR uses ISO 639-1 codes ('en', 'fr') while Tesseract uses
    # ISO 639-2/T codes ('eng', 'fra').  Map on init so callers can always
    # pass the Tesseract-style code and the right engine gets the right code.
    _TESSERACT_TO_EASYOCR: dict[str, str] = {
        "eng": "en", "fra": "fr", "deu": "de", "spa": "es",
        "ita": "it", "por": "pt", "chi_sim": "ch_sim", "chi_tra": "ch_tra",
        "jpn": "ja", "kor": "ko", "ara": "ar", "hin": "hi",
    }

    def __init__(self, lang: str = "eng") -> None:
        self.lang       = lang
        self._easyocr_lang = self._TESSERACT_TO_EASYOCR.get(lang, lang)
        self._backend: str | None = None   # "tesseract" | "easyocr"
        self._reader  = None               # EasyOCR Reader instance if needed

    # -- Initialisation -------------------------------------------------------

    def _init(self) -> None:
        if self._backend is not None:
            return

        # 1. Try Tesseract
        try:
            import pytesseract
            pytesseract.get_tesseract_version()   # raises if binary not found
            self._backend = "tesseract"
            print("[ocr] Engine: Tesseract")
            return
        except Exception:
            pass

        # 2. Try EasyOCR
        try:
            import easyocr  # noqa: F401
            print("[ocr] Loading EasyOCR models (first run downloads ~200 MB) ...")
            import easyocr as _easyocr
            self._reader  = _easyocr.Reader([self._easyocr_lang], verbose=False)
            self._backend = "easyocr"
            print("[ocr] Engine: EasyOCR")
            return
        except ImportError:
            pass

        raise RuntimeError(
            "No OCR engine is installed.\n\n"
            "Option A -- Tesseract (recommended for documents):\n"
            "  1. Download installer: https://github.com/UB-Mannheim/tesseract/wiki\n"
            "  2. pip install pytesseract\n\n"
            "Option B -- EasyOCR (pure Python, no binary needed):\n"
            "  pip install easyocr\n"
        )

    # -- Public API -----------------------------------------------------------

    def extract_text(self, image_bytes: bytes) -> str:
        """
        Run OCR on a rendered page image (raw PNG bytes).
        Returns the recognised text, or '' if nothing could be read.
        """
        self._init()

        from PIL import Image
        try:
            img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        except Exception:
            return ""

        try:
            if self._backend == "tesseract":
                return self._run_tesseract(img)
            else:
                return self._run_easyocr(img)
        except Exception as exc:
            print(f"[ocr] Warning: OCR failed on page -- {exc}")
            return ""

    # -- Backends -------------------------------------------------------------

    def _run_tesseract(self, img) -> str:
        import pytesseract
        # PSM 3  = fully automatic page segmentation, no OSD
        # OEM 3  = default -- LSTM + legacy combined
        config = r"--oem 3 --psm 3"
        text = pytesseract.image_to_string(img, lang=self.lang, config=config)
        return text.strip()

    def _run_easyocr(self, img) -> str:
        import numpy as np
        arr     = np.array(img)
        results = self._reader.readtext(arr, detail=0, paragraph=True)
        return "\n".join(str(r) for r in results).strip()
