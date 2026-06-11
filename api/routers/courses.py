"""
api/routers/courses.py

POST   /api/v1/courses/generate              Start course generation from an ingested document (JSON body)
POST   /api/v1/courses/generate-blueprint    Same, but accepts multipart/form-data — use this when
                                             instructions contain newlines, quotes, or non-ASCII text
GET    /api/v1/courses/jobs/{job_id}         Poll job status + retrieve completed script
GET    /api/v1/courses/library               List all saved course scripts
GET    /api/v1/courses/library/{script_id}   Retrieve a saved course script in full
DELETE /api/v1/courses/library/{script_id}   Delete a saved course script
"""

from fastapi import APIRouter, BackgroundTasks, Body, Depends, Form, HTTPException

from api.config import settings
from api.course_library import library
from api.dependencies import (
    get_embedder,
    get_vector_store,
    generate_course_in_background,
    job_store,
)
from api.schemas import CourseGenerateRequest, CourseGenerateResponse, CourseJobStatus

router = APIRouter(prefix="/api/v1/courses", tags=["Course Generation"])


def _start_course_job(
    source_file:        str,
    course_title:       str | None,
    target_audience:    str,
    instructions:       str | None,
    use_knowledge_base: bool,
    course_format:      str,
    background_tasks:   BackgroundTasks,
    vector_store,
    embedder,
) -> CourseGenerateResponse:
    """Shared logic for both /generate and /generate-blueprint."""
    if not settings.anthropic_api_key:
        raise HTTPException(
            status_code=503,
            detail="ANTHROPIC_API_KEY is not configured. Set it in the .env file.",
        )

    chunks = vector_store.get_all_by_source(source_file)
    if not chunks:
        raise HTTPException(
            status_code=404,
            detail=(
                f"Document '{source_file}' not found in the knowledge base. "
                "Upload and ingest it first via POST /api/v1/documents/upload."
            ),
        )

    job = job_store.create_course(source_file)
    background_tasks.add_task(
        generate_course_in_background,
        job,
        vector_store,
        settings.anthropic_api_key,
        course_title,
        target_audience,
        embedder,
        instructions,
        use_knowledge_base,
        course_format,
    )

    return CourseGenerateResponse(
        job_id=job.job_id,
        status="processing",
        message=(
            f"Course generation started for '{source_file}'. "
            f"Poll /api/v1/courses/jobs/{job.job_id} to track progress."
        ),
    )


@router.post("/generate", response_model=CourseGenerateResponse, status_code=202)
async def generate_course(
    request:          CourseGenerateRequest,
    background_tasks: BackgroundTasks,
    vector_store=Depends(get_vector_store),
    embedder=Depends(get_embedder),
):
    """
    Generate a structured course script from a document already in the knowledge base.

    **Requires** `ANTHROPIC_API_KEY` -- Claude transforms the raw document content
    into educational narration, slide bullets, and visual scene descriptions.

    The three-step generation (analyse -> outline -> script each lesson) runs in
    the background.  Poll **GET /api/v1/courses/jobs/{job_id}** to check progress.
    When `status == "completed"` the full `course_script` JSON is included in
    the response, ready to feed into your PPT / audio / video pipeline.

    **Note:** if your `instructions` contain newlines, double-quotes, or non-ASCII
    characters (e.g. Hindi / Devanagari), use **POST /generate-blueprint** instead,
    which accepts `multipart/form-data` and requires no JSON escaping.
    """
    return _start_course_job(
        source_file=request.source_file,
        course_title=request.course_title,
        target_audience=request.target_audience,
        instructions=request.instructions,
        use_knowledge_base=request.use_knowledge_base,
        course_format=request.course_format,
        background_tasks=background_tasks,
        vector_store=vector_store,
        embedder=embedder,
    )


@router.post("/generate-blueprint", response_model=CourseGenerateResponse, status_code=202)
async def generate_course_from_blueprint(
    background_tasks:   BackgroundTasks,
    vector_store=Depends(get_vector_store),
    embedder=Depends(get_embedder),
    source_file:        str  = Form(...,  description="Filename as stored in the knowledge base"),
    instructions:       str  = Form(...,  description="Full course blueprint — paste raw text, newlines and quotes are fine"),
    course_title:       str  = Form(None, description="Override course title (optional)"),
    target_audience:    str  = Form("learners", description="Who the course is for"),
    use_knowledge_base: bool = Form(False, description="Enrich context from all documents, not just the source file"),
    course_format:      str  = Form("custom", description="'custom' follows the blueprint exactly; 'standard' uses the auto-outline pipeline"),
):
    """
    **Form-data alternative to POST /generate.**

    Use this endpoint when your `instructions` blueprint contains:
    - Multi-line text (raw newlines)
    - Double-quote characters
    - Non-ASCII text (Hindi, Devanagari, Arabic, etc.)

    Send as `multipart/form-data` — no JSON escaping needed.
    Everything else (background job, polling, library storage) works identically.

    **Quick test with curl:**
    ```
    curl -X POST http://localhost:8000/api/v1/courses/generate-blueprint \\
      -F "source_file=First Aid Handbook Final.pdf" \\
      -F "course_format=custom" \\
      -F "target_audience=औद्योगिक / फील्ड कर्मचारी" \\
      -F "instructions=<blueprint.txt"
    ```
    """
    return _start_course_job(
        source_file=source_file,
        course_title=course_title,
        target_audience=target_audience,
        instructions=instructions,
        use_knowledge_base=use_knowledge_base,
        course_format=course_format,
        background_tasks=background_tasks,
        vector_store=vector_store,
        embedder=embedder,
    )


@router.get("/jobs/{job_id}", response_model=CourseJobStatus)
def get_course_job(job_id: str):
    """
    Poll the status of a course generation job.

    When `status == "completed"`, the response includes the full `course_script`
    dictionary containing all modules, lessons, narration scripts, slide content,
    and visual descriptions.
    """
    job = job_store.get_course(job_id)
    if not job:
        raise HTTPException(status_code=404, detail=f"Course job '{job_id}' not found.")
    return job.to_schema()


# -- Course Library -------------------------------------------------------------

@router.get("/library", tags=["Course Library"])
def list_library():
    """
    List all saved course scripts (index only — no script body).
    Returns metadata: script_id, source_file, course_title, target_audience,
    instructions, generated_at, total_lessons, estimated_duration_min.
    """
    return {"scripts": library.list_all(), "total": len(library.list_all())}


@router.get("/library/{script_id}", tags=["Course Library"])
def get_library_script(script_id: str):
    """
    Retrieve a saved course script in full, including the complete course_script JSON.
    """
    record = library.get(script_id)
    if not record:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found in library.")
    return record


@router.get("/library/{script_id}/download", tags=["Course Library"])
def download_script(script_id: str):
    """Download the course_script body as a JSON file."""
    import json as _json
    from fastapi.responses import Response
    record = library.get(script_id)
    if not record:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found in library.")
    content = _json.dumps(record["course_script"], indent=2, ensure_ascii=False)
    safe_title = (record.get("course_title", script_id) or script_id).replace(" ", "_")
    return Response(
        content=content,
        media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="{safe_title}.json"'},
    )


@router.patch("/library/{script_id}", tags=["Course Library"])
def update_library_script(
    script_id:     str,
    course_script: dict       = Body(..., embed=True),
    course_title:  str | None = Body(None, embed=True),
):
    """
    Replace the `course_script` body of a saved course (e.g. after manual edits).
    Supply the full updated `course_script` dict. Optionally update `course_title`.
    """
    updated = library.update(script_id, course_script, course_title)
    if not updated:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found in library.")
    return {"message": "Script updated.", "script_id": script_id}


@router.delete("/library/{script_id}", tags=["Course Library"])
def delete_library_script(script_id: str):
    """Delete a saved course script from the library."""
    existed = library.delete(script_id)
    if not existed:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found in library.")
    return {"message": f"Script '{script_id}' deleted."}
