"""Application settings, loaded from environment / .env file."""
from pathlib import Path

from dotenv import load_dotenv
from pydantic_settings import BaseSettings, SettingsConfigDict

# Always resolve .env relative to this file: backend/.env
# Works regardless of which directory uvicorn is launched from.
_ENV_FILE = Path(__file__).resolve().parent.parent.parent / ".env"

# Pre-load into os.environ so pydantic-settings (and any other library) sees it.
load_dotenv(str(_ENV_FILE), override=True)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=str(_ENV_FILE), extra="ignore")

    # LLM
    anthropic_api_key: str = ""
    llm_provider: str = "anthropic"
    llm_model: str = "claude-3-5-haiku-latest"

    # Video generation (HeyGen)
    heygen_api_key: str = ""
    heygen_base_url: str = "https://api.heygen.com"

    # Voice / TTS
    # "auto"     → Sarvam for Indian languages, edge-tts for everything else
    # "sarvam"   → Sarvam for all languages it supports, edge-tts fallback
    # "edge"     → always use edge-tts (free)
    tts_provider: str = "auto"
    sarvam_api_key: str = ""
    sarvam_base_url: str = "https://api.sarvam.ai"

    # Database
    database_url: str = "sqlite:///./lms.db"


settings = Settings()
