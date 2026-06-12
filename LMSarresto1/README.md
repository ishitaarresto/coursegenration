# Arresto LMS — Course Generation Module

AI-powered safety training video generator.  
Backend: **FastAPI + SQLite** | Frontend: **Flutter Web** | AI: **Claude + HeyGen + edge-tts**

---

## What this module does

- Generates structured safety training courses from raw scripts
- Renders teaching videos in 4 styles (animated, whiteboard, hybrid, HeyGen)
- Supports 70+ languages with auto-translation + TTS
- Includes MCQ knowledge checks embedded in videos
- REST API ready to integrate into any frontend

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Python | 3.11+ | https://python.org |
| Flutter | 3.x | https://flutter.dev |
| ffmpeg | any | https://ffmpeg.org (add to PATH) |
| Git | any | https://git-scm.com |

---

## Setup (first time)

### 1. Clone the repo
```bash
git clone <repo-url>
cd LMSarresto
```

### 2. Backend setup
```bash
cd backend

# Create virtual environment
python -m venv .venv

# Activate (Windows)
.venv\Scripts\activate

# Activate (Mac/Linux)
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Install Playwright browser (for video rendering)
playwright install chromium
```

### 3. Configure environment variables
```bash
# Copy the example file
copy .env.example .env        # Windows
cp .env.example .env          # Mac/Linux

# Open .env and fill in your keys:
# ANTHROPIC_API_KEY  — required  (get from console.anthropic.com)
# HEYGEN_API_KEY     — optional  (for HeyGen video styles)
# SARVAM_API_KEY     — optional  (for Indian-language TTS)
```

### 4. Start the backend
```bash
cd backend
uvicorn app.main:app --reload --port 8000
```

API will be live at: http://localhost:8000  
Swagger docs at:    http://localhost:8000/docs

### 5. Frontend setup (optional — for the Author Studio UI)
```bash
cd frontend
flutter pub get
flutter build web --release
python -m http.server 8080 --directory build/web
```

Open: http://localhost:8080

---

## API Quick Reference

### Courses
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/courses/generate` | Generate course from raw script (LLM) |
| POST | `/api/courses/import` | Import pre-built JSON instantly (no LLM) |
| GET | `/api/courses/{id}` | Get course with modules + lessons |

### Video Rendering
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/courses/{id}/lessons/{id}/render` | Start video render |
| GET | `/api/renders/{id}/status` | Poll render status |
| GET | `/api/courses/{id}/lessons/{id}/video` | Stream MP4 |
| GET | `/api/courses/{id}/lessons/{id}/cost` | Preview credit cost (free) |

### Supporting
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/styles` | List video styles + availability |
| GET | `/api/languages` | List supported languages + TTS engines |
| GET | `/api/jobs/{id}` | Poll generation job status |

---

## Render endpoint parameters

```
POST /api/courses/{course_id}/lessons/{lesson_id}/render
  ?lang=en                  # Language code (en, hi, es, fr, ...)
  ?style=claude_native      # animated_scene | whiteboard_doodle | claude_native | hybrid
  ?course_type=detailed     # detailed (per lesson) | quick (~15 min)
  ?duration_minutes=15      # Target duration
  ?economy=lean             # ultra_lean | lean | standard | full (HeyGen credit budget)
```

---

## Video styles

| Key | Engine | Cost | Best for |
|-----|--------|------|----------|
| `claude_native` | Free (in-house) | ~₹0 | High-volume, any language |
| `animated_scene` | HeyGen | ~₹85/min | Premium cinematic |
| `whiteboard_doodle` | HeyGen | ~₹85/min | Step-by-step procedures |
| `hybrid` | Claude + HeyGen | ~₹40/min | Best cost/quality balance |

---

## Course import JSON format

```json
{
  "course_title": "...",
  "course_description": "...",
  "target_audience": "...",
  "modules": [
    {
      "module_number": 1,
      "module_title": "...",
      "lessons": [
        {
          "lesson_number": 1,
          "lesson_title": "...",
          "duration_minutes": 10,
          "narration_script": "...",
          "learning_objectives": ["..."],
          "slide_content": {
            "title": "...",
            "bullets": ["..."]
          },
          "visual_description": "...",
          "key_terms": ["..."]
        }
      ]
    }
  ]
}
```

---

## Environment variables reference

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | Claude API key (console.anthropic.com) |
| `LLM_MODEL` | No | Default: `claude-haiku-4-5` |
| `DATABASE_URL` | No | Default: `sqlite:///./lms.db` |
| `HEYGEN_API_KEY` | No | HeyGen video generation |
| `SARVAM_API_KEY` | No | Indian-language TTS (Bulbul v3) |

---

## Project structure

```
backend/
  app/
    core/           # Config, DB, settings
    modules/
      course_generation/
        generators/ # TTS, video rendering, scene planning
        models.py   # DB models
        schemas.py  # Pydantic schemas
        service.py  # Background tasks
        router.py   # API endpoints
    providers/
      llm/          # Anthropic Claude connector
      video/        # HeyGen connector
  main.py
  requirements.txt
  .env.example      # Copy to .env and fill in keys

frontend/
  lib/main.dart     # Flutter Author Studio UI
```

---

## Common issues

**`ModuleNotFoundError`** → Run `pip install -r requirements.txt` inside the venv

**`playwright._impl._errors.Error`** → Run `playwright install chromium`

**`ffmpeg not found`** → Install ffmpeg and add to system PATH

**`ANTHROPIC_API_KEY not set`** → Check your `.env` file exists and has the key

**HeyGen 402 error** → Top up Video Agent credits at app.heygen.com → Billing

---

## Integration notes for backend team

- All endpoints return JSON. No authentication yet (add your auth middleware).
- Video files are served as `video/mp4` via `FileResponse` — proxy through your CDN in production.
- SQLite is default; switch to Postgres by setting `DATABASE_URL` in `.env`.
- The `media/` folder stores generated MP4s — mount as a volume in production.
- Background tasks use FastAPI `BackgroundTasks` — replace with Celery for production scale.
