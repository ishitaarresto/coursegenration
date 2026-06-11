"""LLM provider interface and Anthropic implementation.

Forces schema-valid JSON via tool-use so callers always get a valid Pydantic model.
Source content is sent with cache_control=ephemeral so repeated lesson calls against
the same source are cheap (cache hits cost ~10% of input tokens).
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
        """Return an instance of `schema` grounded in `source_content`."""
        raise NotImplementedError


class AnthropicProvider(LLMProvider):
    def __init__(self, api_key: str, model: str) -> None:
        import anthropic
        self.client = anthropic.Anthropic(api_key=api_key)
        self.model = model

    def generate_structured(
        self,
        *,
        system: str,
        instruction: str,
        source_content: str,
        schema: Type[T],
        max_tokens: int = 4096,
    ) -> T:
        import anthropic
        tool = {
            "name": "emit",
            "description": "Emit the requested structured result. You MUST call this tool.",
            "input_schema": schema.model_json_schema(),
        }
        message = self.client.messages.create(
            model=self.model,
            max_tokens=max_tokens,
            system=[{"type": "text", "text": system}],
            tools=[tool],
            tool_choice={"type": "tool", "name": "emit"},
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": f"SOURCE CONTENT (the only source of truth):\n\n{source_content}",
                            "cache_control": {"type": "ephemeral"},
                        },
                        {"type": "text", "text": instruction},
                    ],
                }
            ],
        )
        for block in message.content:
            if block.type == "tool_use" and block.name == "emit":
                return schema.model_validate(block.input)
        raise RuntimeError("Model did not return a tool_use block")


def get_llm() -> LLMProvider:
    """Return a ready-to-use LLM provider using the configured Anthropic key."""
    from api.config import settings
    if not settings.anthropic_api_key:
        raise RuntimeError(
            "ANTHROPIC_API_KEY is not set. Add it to your .env file."
        )
    return AnthropicProvider(api_key=settings.anthropic_api_key, model=settings.llm_model)
