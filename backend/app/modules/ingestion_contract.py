"""Contract between Content Ingestion (Module 1, coworker) and Course Generation.

Module 1 produces cleaned text / knowledge chunks. Course Generation only needs a
single source-of-truth string. This adapter lets us accept either pasted text now,
or a list of chunks from Module 1 later, without changing the generators.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class IngestedContent:
    text: str
    title_hint: str | None = None


def from_pasted_text(text: str, title_hint: str | None = None) -> IngestedContent:
    return IngestedContent(text=text.strip(), title_hint=title_hint)


def from_chunks(chunks: list[str], title_hint: str | None = None) -> IngestedContent:
    """Future hook: Module 1 hands us ordered knowledge chunks."""
    return IngestedContent(text="\n\n".join(c.strip() for c in chunks), title_hint=title_hint)
