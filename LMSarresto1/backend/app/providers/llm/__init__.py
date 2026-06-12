"""LLM provider factory. Swap vendors via LLM_PROVIDER env var."""
from app.core.config import settings
from app.providers.llm.base import LLMProvider


def get_llm() -> LLMProvider:
    provider = settings.llm_provider.lower()
    if provider == "anthropic":
        from app.providers.llm.anthropic_provider import AnthropicProvider

        return AnthropicProvider()
    raise ValueError(f"Unknown LLM_PROVIDER: {settings.llm_provider}")
