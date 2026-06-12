"""Anthropic Claude provider.

- Forces schema-valid JSON via tool-use (model must call the `emit` tool whose
  input_schema is our Pydantic JSON Schema -> we parse/validate the result).
- Prompt-caches the SOURCE CONTENT block so generating many lessons from the
  same course content is cheap (cache hits cost ~10% of input tokens).
"""
from __future__ import annotations

from typing import Type, TypeVar

import anthropic
from pydantic import BaseModel

from app.core.config import settings
from app.providers.llm.base import LLMProvider

T = TypeVar("T", bound=BaseModel)


class AnthropicProvider(LLMProvider):
    def __init__(self) -> None:
        if not settings.anthropic_api_key:
            raise RuntimeError(
                "ANTHROPIC_API_KEY is not set. Copy backend/.env.example to backend/.env "
                "and add your key from https://console.anthropic.com"
            )
        self.client = anthropic.Anthropic(api_key=settings.anthropic_api_key)
        self.model = settings.llm_model

    def generate_structured(
        self,
        *,
        system: str,
        instruction: str,
        source_content: str,
        schema: Type[T],
        max_tokens: int = 4096,
    ) -> T:
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
                        # Cached: identical across all lessons of one course.
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
