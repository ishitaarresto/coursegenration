"""
api/main.py -- FastAPI application entry point.

Startup sequence (lifespan)
---------------------------
1. Initialise VectorStore (opens ChromaDB on disk -- fast)
2. Initialise Embedder (lazy -- model loads on first request)
3. Initialise IngestionPipeline (wraps extractors + chunker + embedder + store)
4. Initialise RetrievalPipeline (bge-m3 + BM25 + reranker + Haiku intent detection)
5. Initialise ProgressTracker (SQLite-backed learner analytics)
6. Initialise Transcriber (optional, requires SARVAM_API_KEY)
7. Initialise TTSEngine (optional, requires OPENAI_API_KEY)

All objects are stored in app.state and injected into routes via FastAPI
dependency injection (see dependencies.py).
"""

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from api.config import settings
from api.routers import documents, chat, courses, tutor, progress, audio, voice, video, compat
from api.schemas import HealthResponse


# -- Lifespan -------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and clean up shared resources."""
    from modules.content_ingestion.embedder     import Embedder
    from modules.content_ingestion.vector_store import VectorStore
    from modules.content_ingestion.chunker      import Chunker
    from modules.content_ingestion.pipeline     import IngestionPipeline

    print("[startup] Initialising Arresto LMS API ...")

    # Database: create all SQLAlchemy-managed tables in lms.db
    from api.db import init_db
    init_db()

    vs = VectorStore(persist_dir=str(settings.chroma_db_dir))
    em = Embedder()

    captioner = None
    if settings.enable_captioning:
        from modules.content_ingestion.captioner import ImageCaptioner
        captioner = ImageCaptioner()
        print("[startup] BLIP-2 captioner enabled (will load on first image).")

    pipeline = IngestionPipeline(
        extract_images=settings.enable_captioning,
        enable_ocr=settings.enable_ocr,
        ocr_lang=settings.ocr_lang,
        captioner=captioner,
        chunker=Chunker(),
        embedder=em,
        vector_store=vs,
    )
    if settings.enable_ocr:
        print(f"[startup] OCR enabled (lang={settings.ocr_lang})")

    app.state.embedder     = em
    app.state.vector_store = vs
    app.state.pipeline     = pipeline

    # Transcriber — Sarvam AI speech-to-text (optional, requires SARVAM_API_KEY)
    app.state.transcriber = None
    if settings.sarvam_api_key:
        try:
            from modules.voice import Transcriber
            app.state.transcriber = Transcriber(
                api_key=settings.sarvam_api_key,
                language=settings.sarvam_language,
            )
            print(f"[startup] Transcriber (Sarvam STT) ready "
                  f"(language={settings.sarvam_language}).")
        except Exception as exc:
            print(f"[startup] WARNING: Transcriber failed to init: {exc}")

    # TTS engine — Sarvam Bulbul-v3 (preferred) or OpenAI (fallback)
    app.state.tts_engine = None
    if settings.sarvam_api_key:
        try:
            from modules.video.generators.sarvam_tts import SarvamTTSEngine
            tts_lang = settings.sarvam_language.lower()
            app.state.tts_engine = SarvamTTSEngine(lang=tts_lang)
            print(f"[startup] TTS engine ready (Sarvam Bulbul-v3, lang={tts_lang}).")
        except Exception as exc:
            print(f"[startup] WARNING: Sarvam TTS engine failed to init: {exc}")
    elif settings.openai_api_key:
        try:
            from modules.tts import TTSEngine
            app.state.tts_engine = TTSEngine(
                api_key=settings.openai_api_key,
                model=settings.tts_model,
                voice=settings.tts_voice,
            )
            print(f"[startup] TTS engine ready "
                  f"(OpenAI {settings.tts_model}, voice={settings.tts_voice}).")
        except ImportError:
            print("[startup] WARNING: openai package not installed. "
                  "Run: pip install openai>=1.0.0")
        except Exception as exc:
            print(f"[startup] WARNING: TTS engine failed to init: {exc}")

    # Intelligent retrieval pipeline (Phases 1-5: bge-m3 + BM25 + Reranker + Intent + Context)
    from modules.progress.tracker import ProgressTracker
    app.state.progress_tracker = ProgressTracker()
    print("[startup] Progress tracker initialised (progress.db).")

    app.state.retrieval_pipeline = None
    if settings.enable_retrieval_pipeline and settings.anthropic_api_key:
        try:
            from modules.retrieval.pipeline import RetrievalPipeline
            app.state.retrieval_pipeline = RetrievalPipeline(
                api_key=settings.anthropic_api_key,
                bge_db_dir=settings.chroma_db_dir_bge,
                enable_reranking=settings.enable_reranking,
                haiku_model=settings.haiku_model,
            )
        except Exception as exc:
            print(f"[startup] WARNING: Retrieval pipeline failed to init: {exc}")
            print("[startup]   Tutor will fall back to basic MiniLM retrieval.")
    elif not settings.enable_retrieval_pipeline:
        print("[startup] Retrieval pipeline disabled (ENABLE_RETRIEVAL_PIPELINE=false).")
    else:
        print("[startup] Retrieval pipeline skipped — ANTHROPIC_API_KEY not set.")

    claude_status = "enabled" if settings.anthropic_api_key else "disabled (set ANTHROPIC_API_KEY)"
    rp_status = "enabled" if app.state.retrieval_pipeline else "disabled"
    print(f"[startup] Ready -- {vs.count()} chunks in DB | Claude: {claude_status} | Retrieval pipeline: {rp_status}")

    yield  # <- server runs here

    print("[shutdown] Arresto LMS API shutting down.")


# -- App ------------------------------------------------------------------------

app = FastAPI(
    title="Arresto LMS -- Content Ingestion API",
    description=(
        "Upload training documents (PDF/DOCX/PPTX), ask questions about them "
        "via RAG, and generate structured course scripts for PPT/audio/video pipelines."
    ),
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # tighten in production
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(documents.router)
app.include_router(chat.router)
app.include_router(courses.router)
app.include_router(tutor.router)
app.include_router(progress.router)
app.include_router(audio.router)
app.include_router(voice.router)
app.include_router(video.router)
app.include_router(compat.router)   # Author Studio (GitHub frontend) compat layer


# -- Root & health --------------------------------------------------------------

@app.get("/api", tags=["Info"])
def root():
    return {
        "service": "Arresto LMS Content Ingestion API",
        "version": "1.0.0",
        "docs":    "/docs",
    }


@app.get("/health", response_model=HealthResponse, tags=["Info"])
def health():
    """System health -- shows DB chunk count, available sources, feature flags."""
    vs = app.state.vector_store
    return HealthResponse(
        status="ok",
        chunks_in_db=vs.count(),
        documents=vs.list_sources(),
        claude_enabled=bool(settings.anthropic_api_key),
        captioning_on=settings.enable_captioning,
        ocr_enabled=settings.enable_ocr,
    )


# -- Flutter web (must be last — StaticFiles("/") is a catch-all) ---------------
_FLUTTER_WEB = (
    Path(__file__).resolve().parent.parent
    / "frontend" / "build" / "web"
)

_NO_CACHE = {"Cache-Control": "no-store, no-cache, must-revalidate"}

# Serve critical Flutter JS files with no-cache headers so rebuilds take effect
# immediately without requiring the user to hard-refresh the browser.
@app.get("/main.dart.js", include_in_schema=False)
def _serve_main_js():
    return FileResponse(str(_FLUTTER_WEB / "main.dart.js"),
                        headers=_NO_CACHE, media_type="application/javascript")

@app.get("/flutter_bootstrap.js", include_in_schema=False)
def _serve_bootstrap_js():
    return FileResponse(str(_FLUTTER_WEB / "flutter_bootstrap.js"),
                        headers=_NO_CACHE, media_type="application/javascript")

@app.get("/flutter_service_worker.js", include_in_schema=False)
def _serve_service_worker_js():
    return FileResponse(str(_FLUTTER_WEB / "flutter_service_worker.js"),
                        headers=_NO_CACHE, media_type="application/javascript")

if _FLUTTER_WEB.exists():
    app.mount(
        "/",
        StaticFiles(directory=str(_FLUTTER_WEB), html=True),
        name="flutter",
    )
