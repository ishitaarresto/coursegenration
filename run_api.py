"""
run_api.py -- Start the Arresto LMS API server.

Usage
    python run_api.py                    # default: http://localhost:8000
    python run_api.py --port 9000        # custom port
    python run_api.py --reload           # auto-reload on code changes (dev)

Environment -- create a .env file in the project root:
    ANTHROPIC_API_KEY=sk-ant-...         required for /chat answers + /courses/generate
    ENABLE_CAPTIONING=false              set true to attach BLIP-2 (slow on CPU)
    CHROMA_DB_DIR=./chroma_db            where ChromaDB persists
    UPLOAD_DIR=./uploads                 where uploaded files are saved
"""

# -- Force UTF-8 I/O BEFORE anything else loads --------------------------------
# Windows uses cp1252 by default. Any print() with a non-ASCII character
# (arrows, dashes, ellipsis) in the pipeline code crashes with UnicodeEncodeError.
# Setting PYTHONIOENCODING here affects the current process AND every child
# process / thread uvicorn spawns.
import os
import sys
import io

os.environ["PYTHONIOENCODING"] = "utf-8"

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, io.UnsupportedOperation):
    # Fallback: replace the wrapper entirely
    if hasattr(sys.stdout, "buffer"):
        sys.stdout = io.TextIOWrapper(
            sys.stdout.buffer, encoding="utf-8", errors="replace", line_buffering=True
        )
    if hasattr(sys.stderr, "buffer"):
        sys.stderr = io.TextIOWrapper(
            sys.stderr.buffer, encoding="utf-8", errors="replace", line_buffering=True
        )

# -- Server ---------------------------------------------------------------------
import argparse
import uvicorn

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Arresto LMS API server")
    parser.add_argument("--host",   default="0.0.0.0", help="Bind host")
    parser.add_argument("--port",   default=8000, type=int, help="Port")
    parser.add_argument("--reload", action="store_true",   help="Auto-reload (dev)")
    args = parser.parse_args()

    print(f"\n  Arresto LMS API  [UTF-8 build]")
    print(f"  URL  : http://localhost:{args.port}")
    print(f"  Docs : http://localhost:{args.port}/docs\n")

    uvicorn.run(
        "api.main:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="info",
    )
