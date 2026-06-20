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

import asyncio
import json as _json
import re as _re

from fastapi import APIRouter, BackgroundTasks, Body, Depends, Form, HTTPException

from api.config import settings
from api.course_library import library
from api.dependencies import (
    get_embedder,
    get_vector_store,
    generate_course_in_background,
    job_store,
)
from api.schemas import (
    CourseGenerateRequest, CourseGenerateResponse, CourseJobStatus, ErrorDetail,
    AssessmentConfigRequest, PublishRequest,
    AssessmentAttemptRequest, AssessmentAttemptItem,
)

router = APIRouter(prefix="/api/v1/courses", tags=["Course Generation"])

_ASSESSMENT_SYSTEM = (
    "You are an expert instructional designer for safety and industrial training. "
    "Your job is to create an engaging assessment quiz that mixes multiple-choice and "
    "true/false questions. Aim for roughly 70% multiple-choice and 30% true/false. "
    "If the course instructions already contain explicit quiz or assessment questions, "
    "extract and use THOSE as the primary source — do not invent new ones when the admin "
    "has provided them. Format them into the required structure. "
    "Generate additional questions from course content only to reach the target count. "
    "Always return valid JSON with no markdown, no explanation, just the JSON object."
)

_ASSESSMENT_SCHEMA = """
Return ONLY a JSON object with this exact structure (no markdown, no explanation).
Mix multiple-choice and true/false questions (roughly 70% MCQ, 30% true/false).

{
  "questions": [
    {
      "type": "mcq",
      "question": "Question text here?",
      "options": {
        "A": "First option text",
        "B": "Second option text",
        "C": "Third option text",
        "D": "Fourth option text"
      },
      "correct_answer": "A",
      "explanation": "Brief explanation of why A is correct."
    },
    {
      "type": "true_false",
      "question": "A clear statement that is definitively true or false?",
      "options": {
        "A": "True",
        "B": "False"
      },
      "correct_answer": "A",
      "explanation": "Brief explanation of why this statement is true."
    }
  ]
}

Rules:
- type must be exactly "mcq" or "true_false"
- For mcq: options must have exactly A, B, C, D; correct_answer is one of A/B/C/D
- For true_false: options must be exactly {"A": "True", "B": "False"}; correct_answer is "A" or "B"
- True/false questions must be clear factual statements, not ambiguous opinions
- Each question must be directly answerable from the course content
"""


def _build_course_summary(course_script: dict) -> str:
    """Build a compact text summary of course content for the LLM."""
    modules = course_script.get("modules", [])
    items   = course_script.get("items", [])
    lines   = []
    if modules:
        for mod in modules:
            lines.append(f"## {mod.get('module_title', 'Module')}")
            for les in mod.get("lessons", []):
                title     = les.get("lesson_title", "")
                narration = (les.get("narration_script", "") or "")[:600]
                lines.append(f"  Lesson: {title}")
                if narration:
                    lines.append(f"  {narration}")
    elif items:
        for item in items:
            title     = item.get("title", "")
            narration = (item.get("narration") or item.get("narration_script") or "")[:600]
            lines.append(f"- {title}: {narration}")
    return "\n".join(lines)[:8000]


def _generate_assessment_questions_sync(
    instructions:  str | None,
    course_script: dict,
    num_questions: int,
    api_key:       str,
) -> list[dict]:
    import anthropic

    course_summary = _build_course_summary(course_script)
    course_title   = course_script.get("course_title", "")

    instructions_block = (
        f"INSTRUCTIONS / DESCRIPTION FROM COURSE DESIGNER:\n{instructions}\n\n"
        if instructions else ""
    )

    user_msg = (
        f"Course: {course_title}\n\n"
        f"{instructions_block}"
        f"COURSE CONTENT SUMMARY:\n{course_summary}\n\n"
        f"Generate exactly {num_questions} assessment questions (mix of MCQ and true/false).\n"
        f"IMPORTANT: If the instructions above already contain quiz questions, "
        f"extract and format THOSE first before generating new ones.\n\n"
        f"{_ASSESSMENT_SCHEMA}"
    )

    client = anthropic.Anthropic(api_key=api_key)
    resp   = client.messages.create(
        model=settings.llm_model,
        max_tokens=4000,
        system=_ASSESSMENT_SYSTEM,
        messages=[{"role": "user", "content": user_msg}],
    )
    raw = resp.content[0].text.strip()
    raw = _re.sub(r'^```(?:json)?\s*', '', raw)
    raw = _re.sub(r'\s*```$', '', raw)

    data      = _json.loads(raw)
    questions = []
    for i, q in enumerate(data.get("questions", []), start=1):
        questions.append({
            "id":             f"aq_{i}",
            "type":           q.get("type", "mcq"),
            "question":       q["question"],
            "options":        q["options"],
            "correct_answer": q["correct_answer"],
            "explanation":    q.get("explanation", ""),
        })
    return questions


def _start_course_job(
    source_file:        str,
    course_title:       str | None,
    target_audience:    str,
    instructions:       str | None,
    user_instructions:  str | None,
    use_knowledge_base: bool,
    course_format:      str,
    language:           str,
    duration_range:     str,
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
        language,
        duration_range,
        user_instructions,
    )

    return CourseGenerateResponse(
        job_id=job.job_id,
        status="processing",
        message=(
            f"Course generation started for '{source_file}'. "
            f"Poll /api/v1/courses/jobs/{job.job_id} to track progress."
        ),
    )


@router.post("/generate", response_model=CourseGenerateResponse, status_code=202,
             responses={404: {"model": ErrorDetail}, 503: {"model": ErrorDetail}})
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
        user_instructions=request.user_instructions,
        use_knowledge_base=request.use_knowledge_base,
        course_format=request.course_format,
        language=request.language,
        duration_range=request.duration_range,
        background_tasks=background_tasks,
        vector_store=vector_store,
        embedder=embedder,
    )


@router.post("/generate-blueprint", response_model=CourseGenerateResponse, status_code=202,
             responses={404: {"model": ErrorDetail}, 503: {"model": ErrorDetail}})
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
    language:           str  = Form("English", description="Language for all course content"),
    duration_range:     str  = Form("60-90 minutes", description="Target duration: '30-45 minutes', '60-90 minutes', '2-3 hours', '3+ hours'"),
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
        user_instructions=None,
        use_knowledge_base=use_knowledge_base,
        course_format=course_format,
        language=language,
        duration_range=duration_range,
        background_tasks=background_tasks,
        vector_store=vector_store,
        embedder=embedder,
    )


@router.get("/jobs/{job_id}", response_model=CourseJobStatus,
            responses={404: {"model": ErrorDetail}})
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
    scripts = library.list_all()
    return {"scripts": scripts, "total": len(scripts)}


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


@router.patch("/library/{script_id}/assessment-config", tags=["Course Library"])
def save_assessment_config(script_id: str, req: AssessmentConfigRequest):
    """
    Store the assessment configuration (questions, pass %, time, retakes) for a course.
    Called by the admin generator wizard after the learner configures the assessment step.
    """
    ok = library.save_assessment_config(
        script_id=script_id,
        num_questions=req.num_questions,
        pass_pct=req.pass_pct,
        time_min=req.time_min,
        retakes=req.retakes,
    )
    if not ok:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found.")
    return {"message": "Assessment config saved.", "script_id": script_id}


@router.post("/library/{script_id}/publish", tags=["Course Library"])
def publish_course(script_id: str, req: PublishRequest):
    """
    Publish or unpublish a course. Sets the published flag so learners can access it.
    """
    published = req.publish_mode != "draft"
    ok = library.publish(script_id, published=published)
    if not ok:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found.")
    status = "published" if published else "draft"
    return {
        "message": f"Course {status}.",
        "script_id": script_id,
        "published": published,
        "publish_mode": req.publish_mode,
    }


@router.delete("/library/{script_id}", tags=["Course Library"])
def delete_library_script(script_id: str):
    """Delete a saved course script from the library."""
    existed = library.delete(script_id)
    if not existed:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found in library.")
    return {"message": f"Script '{script_id}' deleted."}


@router.get("/library/{script_id}/assessment-questions", tags=["Course Library"])
async def get_assessment_questions(script_id: str, regenerate: bool = False):
    """
    Return assessment quiz questions for a course.

    Questions are generated from the course instructions (which may contain
    explicit quiz questions written by the admin) plus the full course script.
    Results are cached in the DB — pass ?regenerate=true to force a fresh run.
    """
    record = library.get(script_id)
    if not record:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found.")

    if not regenerate:
        cached = library.get_assessment_questions(script_id)
        if cached:
            return {"questions": cached, "cached": True}

    if not settings.anthropic_api_key:
        raise HTTPException(
            status_code=503,
            detail="ANTHROPIC_API_KEY not configured — assessment generation unavailable.",
        )

    num_questions = record.get("assessment_num_questions", 5)

    try:
        questions = await asyncio.to_thread(
            _generate_assessment_questions_sync,
            record.get("instructions"),
            record["course_script"],
            num_questions,
            settings.anthropic_api_key,
        )
    except _json.JSONDecodeError as exc:
        raise HTTPException(status_code=500, detail=f"LLM returned invalid JSON: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Assessment generation failed: {exc}")

    library.save_assessment_questions(script_id, questions)
    return {"questions": questions, "cached": False}


@router.post("/library/{script_id}/assessment-attempts", tags=["Course Library"],
             status_code=201)
async def save_assessment_attempt(script_id: str, req: AssessmentAttemptRequest):
    """
    Record a completed assessment attempt for a learner.
    Called by the Flutter app immediately after the learner submits the quiz.
    """
    import uuid
    import time as _time
    from api.db import SessionLocal
    from api.models.progress import AssessmentAttemptRow

    record = library.get(script_id)
    if not record:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found.")

    with SessionLocal() as db:
        row = AssessmentAttemptRow(
            id=str(uuid.uuid4()),
            learner_id=req.learner_id,
            script_id=script_id,
            score=req.score,
            correct=req.correct,
            total=req.total,
            passed=1 if req.passed else 0,
            elapsed_seconds=req.elapsed_seconds,
            answers_json=_json.dumps(req.answers, ensure_ascii=False),
            taken_at=_time.time(),
        )
        db.add(row)
        db.commit()

    if req.passed:
        try:
            from api.notification_store import push as _notif
            course_title = (record.get("course_title") or script_id)
            _notif(
                req.learner_id,
                "Certificate Earned",
                f'You passed "{course_title}" with {req.score}%! Your certificate is ready.',
                "🎓",
                "certificate_earned",
            )
        except Exception:
            pass

    return {"message": "Attempt saved.", "id": row.id}


@router.get("/library/{script_id}/assessment-attempts", tags=["Course Library"],
            response_model=dict)
def get_assessment_attempts(script_id: str, learner_id: str):
    """
    Retrieve all assessment attempts for a learner on a course, newest first.
    """
    from api.db import SessionLocal
    from api.models.progress import AssessmentAttemptRow
    from sqlalchemy import desc

    record = library.get(script_id)
    if not record:
        raise HTTPException(status_code=404, detail=f"Script '{script_id}' not found.")

    with SessionLocal() as db:
        rows = (
            db.query(AssessmentAttemptRow)
            .filter(
                AssessmentAttemptRow.script_id == script_id,
                AssessmentAttemptRow.learner_id == learner_id,
            )
            .order_by(desc(AssessmentAttemptRow.taken_at))
            .all()
        )
        attempts = [
            AssessmentAttemptItem(
                id=r.id,
                score=r.score,
                correct=r.correct,
                total=r.total,
                passed=bool(r.passed),
                elapsed_seconds=r.elapsed_seconds,
                taken_at=r.taken_at,
            ).model_dump()
            for r in rows
        ]
    return {"attempts": attempts, "total": len(attempts)}
