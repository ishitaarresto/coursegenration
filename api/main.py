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

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from fastapi import Request
from fastapi.responses import JSONResponse

from api.config import settings
from api.routers import documents, chat, courses, tutor, progress, audio, voice, video, questions, tts
from api.schemas import HealthResponse

# -- Logging setup --------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("arresto.api")


# -- Lifespan -------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and clean up shared resources."""
    from modules.content_ingestion.embedder     import Embedder
    from modules.content_ingestion.vector_store import VectorStore
    from modules.content_ingestion.chunker      import Chunker
    from modules.content_ingestion.pipeline     import IngestionPipeline

    logger.info("Initialising Arresto LMS API ...")

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
            logger.info("Transcriber (Sarvam STT) ready (language=%s)", settings.sarvam_language)
        except Exception as exc:
            logger.warning("Transcriber failed to init: %s", exc)

    # TTS engine — Sarvam Bulbul-v3 (preferred) or OpenAI (fallback)
    app.state.tts_engine = None
    if settings.sarvam_api_key:
        try:
            from modules.video.generators.sarvam_tts import SarvamTTSEngine
            tts_lang = settings.sarvam_language.lower()
            app.state.tts_engine = SarvamTTSEngine(lang=tts_lang)
            logger.info("TTS engine ready (Sarvam Bulbul-v3, lang=%s)", tts_lang)
        except Exception as exc:
            logger.warning("Sarvam TTS engine failed to init: %s", exc)
    elif settings.openai_api_key:
        try:
            from modules.tts import TTSEngine
            app.state.tts_engine = TTSEngine(
                api_key=settings.openai_api_key,
                model=settings.tts_model,
                voice=settings.tts_voice,
            )
            logger.info("TTS engine ready (OpenAI %s, voice=%s)", settings.tts_model, settings.tts_voice)
        except ImportError:
            logger.warning("openai package not installed — run: pip install openai>=1.0.0")
        except Exception as exc:
            logger.warning("TTS engine failed to init: %s", exc)

    # Progress tracker — writes to lms.db (same file as ORM tables)
    from modules.progress.tracker import ProgressTracker
    from modules.progress.store   import ProgressStore
    app.state.progress_tracker = ProgressTracker(store=ProgressStore("lms.db"))
    logger.info("Progress tracker initialised (lms.db)")

    # Pre-warm OCR engine in the background so the first document upload
    # doesn't stall while EasyOCR downloads its language models (~150 MB).
    if settings.enable_ocr:
        import threading
        from modules.content_ingestion.ocr import OCREngine
        def _warm_ocr() -> None:
            try:
                OCREngine(settings.ocr_lang)._init()
                logger.info("OCR engine pre-warmed (lang=%s)", settings.ocr_lang)
            except Exception as exc:
                logger.warning("OCR pre-warm failed: %s", exc)
        threading.Thread(target=_warm_ocr, daemon=True, name="ocr-prewarm").start()

    app.state.retrieval_pipeline = None
    if settings.enable_retrieval_pipeline and settings.anthropic_api_key:
        try:
            from modules.retrieval.pipeline import RetrievalPipeline
            app.state.retrieval_pipeline = RetrievalPipeline(
                api_key=settings.anthropic_api_key,
                bge_db_dir=settings.chroma_db_dir_bge,
                enable_reranking=settings.enable_reranking,
                haiku_model=settings.haiku_model,
                top_candidates=30,
                top_final=8,
            )
        except Exception as exc:
            logger.warning("Retrieval pipeline failed to init: %s", exc)
            logger.warning("  Tutor will fall back to basic MiniLM retrieval.")
    elif not settings.enable_retrieval_pipeline:
        logger.info("Retrieval pipeline disabled (ENABLE_RETRIEVAL_PIPELINE=false)")
    else:
        logger.info("Retrieval pipeline skipped — ANTHROPIC_API_KEY not set")

    claude_status = "enabled" if settings.anthropic_api_key else "disabled (set ANTHROPIC_API_KEY)"
    rp_status = "enabled" if app.state.retrieval_pipeline else "disabled"
    logger.info(
        "Ready — %d chunks in DB | Claude: %s | Retrieval pipeline: %s",
        vs.count(), claude_status, rp_status,
    )

    yield  # <- server runs here

    logger.info("Arresto LMS API shutting down.")


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
app.include_router(questions.router)
app.include_router(tts.router)


# -- Global exception handler ---------------------------------------------------
# Catches any unhandled Python exception that escapes a route handler and returns
# a clean JSON 500 instead of leaking tracebacks to the client.

@app.exception_handler(Exception)
async def _unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled exception on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error. Please try again or contact support."},
    )


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
    / "frontend-lms" / "build" / "web"
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
