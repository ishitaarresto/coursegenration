# LMS Backend — Course Generation Module

FastAPI modular monolith. This is **Module 2: Course Generation** — turns source
content into a structured, factually-grounded, interactive course (text + slides).

## Setup (Windows / PowerShell)
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env      # then edit .env and add your ANTHROPIC_API_KEY
```

## Run
```powershell
uvicorn app.main:app --reload
```
Open http://127.0.0.1:8000/docs for interactive API docs.

## Generate a course
1. `POST /api/courses/generate` with body:
   ```json
   { "content_text": "<paste your script>", "mode": "detailed", "languages": ["en"] }
   ```
   Returns a `job` id.
2. Poll `GET /api/jobs/{id}` until `status` = `completed` (gives `course_id`).
3. `GET /api/courses/{course_id}` — full structured course.
4. `GET /api/courses/{course_id}/lessons/{lesson_id}/slides` — interactive reveal.js deck.

A ready-made test script is in `sample_script.txt`.

## Structure
- `app/providers/llm/` — pluggable LLM (Claude default; swap via `LLM_PROVIDER`).
- `app/modules/course_generation/` — models, schemas, prompts, generators, service, router.
- `app/modules/ingestion_contract.py` — adapter for Module 1 (Content Ingestion).
