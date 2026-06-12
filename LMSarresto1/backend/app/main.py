"""FastAPI app — serves API + Flutter web from one server on port 8000."""
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.core.db import init_db
from app.modules.course_generation.router import router as course_gen_router

app = FastAPI(title="AI-Powered LMS", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _startup() -> None:
    init_db()


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


# ── API routes (always take priority) ─────────────────────────
app.include_router(course_gen_router)

# ── Flutter web build ──────────────────────────────────────────
_WEB = (
    Path(__file__).resolve().parent.parent.parent
    / "frontend" / "build" / "web"
)


if _WEB.exists():
    # Mount ALL Flutter static assets (JS, CSS, fonts, canvaskit, icons…)
    # under the root. API routes registered above take priority.
    app.mount("/", StaticFiles(directory=str(_WEB), html=True), name="flutter")
