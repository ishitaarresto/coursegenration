"""
api/config.py -- All settings read from environment variables or .env file.

Create a .env file in the project root:
    ANTHROPIC_API_KEY=sk-ant-...
    UPLOAD_DIR=./uploads
    CHROMA_DB_DIR=./chroma_db
    ENABLE_CAPTIONING=false
"""

from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Anthropic -- required for /chat answers and /courses/generate
    anthropic_api_key: str = ""

    # OpenAI -- required for TTS (lesson narration audio)
    openai_api_key: str = ""
    tts_model:      str = "tts-1"       # tts-1 | tts-1-hd
    tts_voice:      str = "onyx"        # alloy | echo | fable | onyx | nova | shimmer

    # Sarvam AI -- STT (voice transcription) + TTS (Indian-language narration)
    # Get your key at https://dashboard.sarvam.ai
    sarvam_api_key:  str = ""
    sarvam_language: str = "hi-IN"      # hi-IN | en-IN | ta-IN | te-IN | bn-IN | kn-IN | ml-IN | mr-IN | gu-IN | or-IN | pa-IN
    sarvam_base_url: str = "https://api.sarvam.ai"

    # Video generation -- TTS engine selection
    # "auto"   -> Sarvam for Indian languages (hi/ta/te/bn/gu/kn/ml/mr/pa/od), edge-tts for all others
    # "sarvam" -> force Sarvam for every language it supports
    # "edge"   -> always use edge-tts (free, no key needed)
    tts_provider: str = "auto"

    # HeyGen -- optional premium avatar-video rendering
    # Leave blank to use the free animated renderer instead
    # Get a key at https://app.heygen.com
    heygen_api_key:  str = ""
    heygen_base_url: str = "https://api.heygen.com"

    # Storage
    upload_dir:    Path = Path("./uploads")
    chroma_db_dir: str  = "./chroma_db"

    # Server
    host: str = "0.0.0.0"
    port: int  = 8000

    # BLIP-2 captioning (very slow on CPU -- leave off during development)
    enable_captioning: bool = False

    # OCR for scanned PDFs (requires Tesseract binary or easyocr package)
    enable_ocr: bool = False
    ocr_lang:   str  = "eng"

    # LLM model for course generation and video planning
    llm_model: str = "claude-sonnet-4-6"

    # Intelligent retrieval pipeline (Phases 1-5)
    # Requires: pip install rank-bm25
    # bge-m3 and cross-encoder models download on first startup (~2.4 GB total, then cached)
    enable_retrieval_pipeline: bool = True
    chroma_db_dir_bge:         str  = "./chroma_db_bge_comparison"
    enable_reranking:          bool = True
    haiku_model:               str  = "claude-haiku-4-5-20251001"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
settings.upload_dir.mkdir(parents=True, exist_ok=True)
