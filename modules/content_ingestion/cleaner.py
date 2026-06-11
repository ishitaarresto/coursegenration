"""
Text normalization and cleaning for extracted content.

Called by the pipeline after raw text is extracted from a file. Operates on
individual ExtractedPage / ExtractedSlide objects and writes the result into
their `cleaned_text` field, leaving `raw_text` untouched for debugging.

Cleaning steps (applied in order):
1. Unicode normalization -- NFC form, collapse zero-width characters
2. Ligature expansion -- "ﬁ" -> "fi", "ﬂ" -> "fl", etc. (common in PDF fonts)
3. Hyphen de-duplication -- rejoin words split across line breaks ("effec-\ntive" -> "effective")
4. Whitespace normalization -- collapse runs of spaces/tabs, strip leading/trailing whitespace per paragraph
5. Header/footer heuristics -- detect and strip repeated page headers and footers
   based on near-duplicate lines appearing on every page
6. Boilerplate removal -- strip watermark strings, confidentiality notices, or
   other repeated decorative text that adds noise to downstream chunking
7. Control character removal -- strip non-printable characters (except \\n and \\t)

The cleaner is stateless and side-effect-free; it returns new strings rather
than mutating in place so it can be used safely in parallel pipelines.
"""

import re
import unicodedata
from collections import Counter

from modules.content_ingestion.models import ExtractedContent


# -- Constants ------------------------------------------------------------------

# f-ligatures and st-ligatures are the most common PDF font substitutions.
# Keys are Unicode ligature code points; values are their ASCII expansions.
_LIGATURES: dict[str, str] = {
    'ﬀ': 'ff',
    'ﬁ': 'fi',
    'ﬂ': 'fl',
    'ﬃ': 'ffi',
    'ﬄ': 'ffl',
    'ﬅ': 'st',
    'ﬆ': 'st',
}

# Invisible formatting characters that add no meaning to extracted text.
# Includes soft hyphen (­) -- a hyphenation hint that is invisible when
# rendered but appears as a literal character in raw PDF extractions.
_ZERO_WIDTH = '​‌‍‎‏﻿­'

# Common boilerplate patterns found in corporate / educational PDFs.
# Each entry is a compiled regex that matches a full line (case-insensitive).
_BOILERPLATE_PATTERNS: list[re.Pattern] = [
    re.compile(r'^\s*confidential\s*$', re.IGNORECASE),
    re.compile(r'^\s*draft\s*$', re.IGNORECASE),
    re.compile(r'^\s*do not distribute\s*$', re.IGNORECASE),
    re.compile(r'^\s*for internal use only\s*$', re.IGNORECASE),
    re.compile(r'^\s*all rights reserved\.?\s*$', re.IGNORECASE),
    re.compile(r'^\s*(page\s*)?\d+\s*(of\s*\d+)?\s*$', re.IGNORECASE),
]


# -- Public entry point ---------------------------------------------------------

def clean(content: ExtractedContent) -> ExtractedContent:
    """
    Run all normalization steps on every page/slide in `content`.

    Populates `cleaned_text` on each page/slide and also sets
    `content.full_text` to the concatenated cleaned text.
    Returns the same `content` object (mutated in place for efficiency).
    """
    if content.pages:
        # PDF: strip repeated headers/footers across all pages first (step 5),
        # then apply per-block cleaning. OCR pages get an extra noise-removal pass.
        raw_texts = [p.raw_text for p in content.pages]
        deheadered = _strip_repeated_lines(raw_texts)
        for page, text in zip(content.pages, deheadered):
            cleaned = _clean_block(text)
            if page.is_ocr:
                cleaned = _clean_ocr_noise(cleaned)
            page.cleaned_text = cleaned
        content.full_text = '\n\n'.join(
            p.cleaned_text for p in content.pages if p.cleaned_text
        )

    elif content.slides:
        # PPTX: slides are independent -- no cross-slide header stripping needed.
        for slide in content.slides:
            slide.cleaned_text = _clean_block(slide.raw_text)
            if slide.speaker_notes:
                slide.speaker_notes = _clean_block(slide.speaker_notes)
        content.full_text = '\n\n'.join(
            s.cleaned_text for s in content.slides if s.cleaned_text
        )

    else:
        # DOCX: single text blob (no page boundaries exposed by python-docx).
        content.full_text = _clean_block(content.full_text)

    return content


# -- Per-block pipeline ---------------------------------------------------------

def _clean_block(text: str) -> str:
    """Apply steps 1-4 and 6-7 to a single text block."""
    if not text:
        return text
    text = _normalize_unicode(text)      # step 1
    text = _expand_ligatures(text)       # step 2
    text = _rejoin_hyphenated_words(text)  # step 3
    text = _normalize_whitespace(text)   # step 4
    text = _remove_boilerplate(text)     # step 6
    text = _remove_control_chars(text)   # step 7
    return text


# -- Step implementations -------------------------------------------------------

def _normalize_unicode(text: str) -> str:
    """NFC normalization and zero-width character removal."""
    # NFC composes precomposed characters (e.g. "é" -> "é") so downstream
    # comparisons and tokenisation work on a consistent byte representation.
    text = unicodedata.normalize('NFC', text)
    return text.translate(str.maketrans('', '', _ZERO_WIDTH))


def _expand_ligatures(text: str) -> str:
    """Replace typographic ligatures with their ASCII equivalents."""
    for ligature, expansion in _LIGATURES.items():
        text = text.replace(ligature, expansion)
    return text


def _rejoin_hyphenated_words(text: str) -> str:
    """Detect and rejoin words broken by hyphens at line boundaries.

    PDF renderers insert a visible hyphen when a word is broken across two
    lines. After extraction the newline survives, giving patterns like:
        "effec-\\ntive"  ->  should become "effective"
        "Self-\\nAwareness"  ->  should become "Self-Awareness"

    Heuristic: if both sides of the hyphen are lowercase the break is
    typographic (drop the hyphen). If the right side is capitalised it is
    an intentional compound (keep the hyphen, drop only the newline).
    """
    # Broken lowercase word -- drop hyphen and newline
    text = re.sub(r'([a-z])-\n([a-z])', r'\1\2', text)
    # Intentional compound with line break -- keep hyphen, drop newline
    text = re.sub(r'([A-Za-z])-\n([A-Z])', r'\1-\2', text)
    return text


def _normalize_whitespace(text: str) -> str:
    """Collapse runs of whitespace; preserve paragraph breaks."""
    # Collapse runs of spaces and tabs to a single space
    text = re.sub(r'[ \t]+', ' ', text)
    # Strip leading/trailing space from each individual line
    text = '\n'.join(line.strip() for line in text.splitlines())
    # Collapse 3+ consecutive blank lines to a single paragraph break
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def _strip_repeated_lines(pages_text: list[str]) -> list[str]:
    """Identify lines that appear on nearly every page (headers/footers)
    and remove them from all pages.

    Only the first two and last two non-empty lines of each page are
    considered candidates -- headers and footers always live at the edges.
    A line is "repeated" if it appears on at least 60 % of pages (min 2).
    Very short tokens (fewer than 4 characters) are skipped so lone page
    numbers do not accidentally match across pages.
    """
    if len(pages_text) < 2:
        return pages_text

    threshold = max(2, round(len(pages_text) * 0.6))

    line_count: Counter[str] = Counter()
    for text in pages_text:
        non_empty = [l.strip() for l in text.splitlines() if l.strip()]
        edge = set(non_empty[:2] + non_empty[-2:])
        for line in edge:
            if len(line) >= 4:
                line_count[line] += 1

    repeated = {line for line, count in line_count.items() if count >= threshold}
    if not repeated:
        return pages_text

    return [
        '\n'.join(line for line in text.splitlines() if line.strip() not in repeated)
        for text in pages_text
    ]


def _remove_boilerplate(text: str) -> str:
    """Strip lines matching known boilerplate patterns (watermarks, notices)."""
    lines = text.splitlines()
    cleaned = [
        line for line in lines
        if not any(pat.match(line) for pat in _BOILERPLATE_PATTERNS)
    ]
    return '\n'.join(cleaned)


def _clean_ocr_noise(text: str) -> str:
    """
    Remove artifacts specific to OCR-extracted text.

    OCR engines commonly produce:
      - Isolated single characters on their own lines (stray 'l', 'I', '1')
        caused by noise pixels being misread as characters
      - Lines containing only punctuation with no alphanumeric content
        (e.g. "........" or "- - -" from ruled lines in the original page)
      - Multiple consecutive spaces left by character-spacing detection errors

    These are filtered line-by-line. Lines with real content (>=2 alphanumeric
    characters) are kept unchanged.
    """
    lines = text.splitlines()
    kept: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            kept.append(line)          # preserve blank lines (paragraph breaks)
            continue
        alnum_count = sum(1 for c in stripped if c.isalnum())
        if alnum_count < 2:
            continue                   # drop: single char, lone punct, ruled lines
        kept.append(line)
    # Collapse any runs of 3+ blank lines that the dropping may have created
    result = '\n'.join(kept)
    result = re.sub(r'\n{3,}', '\n\n', result)
    return result.strip()


def _remove_control_chars(text: str) -> str:
    """Strip non-printable control characters, preserving newlines and tabs."""
    # unicodedata.category returns 'Cc' for C0/C1 controls, 'Cf' for format
    # characters, 'Cs' for surrogates, 'Co' for private-use. All start with 'C'.
    # \n and \t are Cc but are meaningful whitespace -- exempt them explicitly.
    return ''.join(
        ch for ch in text
        if ch in '\n\t' or not unicodedata.category(ch).startswith('C')
    )
