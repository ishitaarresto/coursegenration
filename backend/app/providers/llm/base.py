"""Thin, vendor-neutral LLM interface.

`generate_structured` returns JSON validated against the given Pydantic model.
`source_content` is passed separately so providers can cache it (cheap reuse
across many lessons of the same course).
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Type, TypeVar

from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)


class LLMProvider(ABC):
    @abstractmethod
    def generate_structured(
        self,
        *,
        system: str,
        instruction: str,
        source_content: str,
        schema: Type[T],
        max_tokens: int = 4096,
    ) -> T:
        """Return an instance of `schema`, grounded in `source_content`."""
        raise NotImplementedError
