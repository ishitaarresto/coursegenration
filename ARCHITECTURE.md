# Arresto LMS — Architecture Document

**Version:** 1.0  
**Date:** June 2026  
**Project:** Arresto LMS (Learning Management System)  
**Stack:** FastAPI · Flutter Web · SQLite · ChromaDB · Claude AI · Sarvam AI · HeyGen

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Module 1 — Application Bootstrap](#2-module-1--application-bootstrap)
3. [Module 2 — Content Ingestion](#3-module-2--content-ingestion)
4. [Module 3 — Course Generation](#4-module-3--course-generation)
5. [Module 4 — Retrieval Pipeline (RAG)](#5-module-4--retrieval-pipeline-rag)
6. [Module 5 — AI Chat (Arresto AI)](#6-module-5--ai-chat-arresto-ai)
7. [Module 6 — AI Tutor](#7-module-6--ai-tutor)
8. [Module 7 — Video Generation](#8-module-7--video-generation)
9. [Module 8 — Progress Tracking](#9-module-8--progress-tracking)
10. [Module 9 — Assessments](#10-module-9--assessments)
11. [Module 10 — Analytics](#11-module-10--analytics)
12. [Module 11 — Flutter Frontend](#12-module-11--flutter-frontend)
13. [Data Storage](#13-data-storage)
14. [External Services](#14-external-services)
15. [Full Learner Journey](#15-full-learner-journey)

---

## 1. System Overview

Arresto LMS is a **monolithic Python + Flutter application**. A single FastAPI process handles everything — REST API, AI logic, and Flutter web delivery. There are no separate microservices.

```
Browser / Flutter Web
        │  HTTP
        ▼
  FastAPI  (api/main.py)
  ├── REST API        /api/v1/...
  └── Static Files    /  →  frontend-lms/build/web/
        │
        ├── SQLite              lms.db
        ├── ChromaDB (MiniLM)   chroma_db/
        ├── ChromaDB (bge-m3)   chroma_db_bge_comparison/
        ├── File storage        uploads/   media/
        └── External APIs       Claude · Sarvam · HeyGen · edge-tts
```

### High-Level Module Map

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FLUTTER WEB FRONTEND                         │
│                                                                     │
│   ADMIN PORTAL                       LEARNER PORTAL                 │
│   ─────────────────────              ──────────────────────────     │
│   Course Generator Wizard            Lesson Player (Video + AI)     │
│   All Courses + Publish              Assessment Quiz                │
│   Learner Management                 Arresto AI Chat                │
│   Analytics Dashboard                Progress + Certificates        │
└────────────────────────────┬────────────────────────────────────────┘
                             │ HTTP / Dio
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         FastAPI BACKEND                             │
│                                                                     │
│  /documents   /courses   /video   /chat   /tutor   /progress        │
│  /voice       /audio     /tts     /assessments      /analytics      │
└───────┬───────────┬──────────┬──────────┬───────────────────────────┘
        │           │          │          │
        ▼           ▼          ▼          ▼
   Content      Course      Video     Retrieval
   Ingestion   Generation  Renderer   Pipeline
   Module       Module      Module    (RAG)
        │           │          │          │
        └───────────┴──────────┴──────────┘
                             │
                    ┌────────┴────────┐
                    ▼                 ▼
              lms.db (SQLite)     ChromaDB x2
              uploads/ media/     (MiniLM + bge-m3)
```

---

## 2. Module 1 — Application Bootstrap

### Purpose
Start all shared resources and wire them into FastAPI's dependency-injection system. All heavy objects (models, DB connections, pipelines) are created once at startup and reused across every request.

### Entry Point
`api/main.py`

### Main Files

| File | Role |
|------|------|
| `api/main.py` | FastAPI app, lifespan, router registration, static file serving |
| `api/config.py` | All settings from `.env` (API keys, paths, feature flags) |
| `api/db.py` | SQLAlchemy engine + `SessionLocal` factory |
| `api/dependencies.py` | `Depends(get_*)` injectors for routers |
| `api/models/__init__.py` | All ORM model imports for `init_db()` |

### Startup Sequence (in order)

```
1. init_db()               → create all SQLite tables
2. VectorStore             → open MiniLM ChromaDB
3. Embedder                → lazy sentence-transformers model
4. IngestionPipeline       → extractors + chunker + embedder + store
5. Transcriber             → Sarvam STT (requires SARVAM_API_KEY)
6. TTSEngine               → Sarvam preferred, OpenAI fallback
7. ProgressTracker         → SQLite-backed learner analytics
8. RetrievalPipeline       → bge-m3 + BM25 + cross-encoder reranker
```

All objects are stored on `app.state`. Routers access them via `Depends(get_*)` in `api/dependencies.py`.

### Data Flow

```
Server starts
  → lifespan() runs all initialisation in order
  → app.state.pipeline, app.state.tracker, etc. populated
  → Routers registered (courses, video, chat, tutor, progress, ...)
  → StaticFiles mounted at "/" (catch-all, serves Flutter build)
  → Server ready to accept requests
```

### Key Configuration (`api/config.py`)

| Setting | Default | Purpose |
|---------|---------|---------|
| `ANTHROPIC_API_KEY` | — | Required for AI features |
| `SARVAM_API_KEY` | — | Indian-language TTS + STT |
| `HEYGEN_API_KEY` | — | Premium video generation |
| `TTS_PROVIDER` | `auto` | `auto` / `sarvam` / `edge` |
| `ENABLE_RETRIEVAL_PIPELINE` | `true` | Enable bge-m3 + reranker |
| `LLM_MODEL` | `claude-sonnet-4-6` | Main generation model |

---

## 3. Module 2 — Content Ingestion

### Purpose
Turn uploaded documents (PDF, DOCX, PPTX, TXT) into clean, searchable vector chunks stored in ChromaDB. This is the knowledge base that powers course generation and AI chat.

### Entry Point
`modules/content_ingestion/pipeline.py` → `IngestionPipeline.run(asset)`

### Main Files

| File | Role |
|------|------|
| `pipeline.py` | Orchestrator — 7-step pipeline |
| `extractors/pdf.py` | PDF text + image extraction (PyMuPDF) |
| `extractors/docx.py` | DOCX paragraph extraction |
| `extractors/pptx.py` | PPTX slide-by-slide extraction |
| `extractors/txt.py` | Plain text and CSV |
| `cleaner.py` | Unicode / ligature / whitespace normalisation |
| `chunker.py` | Splits text into `Chunk` objects with page provenance |
| `embedder.py` | MiniLM sentence-transformers encoding |
| `vector_store.py` | ChromaDB upsert / query (MiniLM store) |
| `captioner.py` | Optional BLIP-2 image captions |
| `ocr.py` | Optional EasyOCR for scanned pages |
| `api/routers/documents.py` | Upload endpoints, triggers pipeline |

### Data Flow

```
POST /api/v1/documents/upload
  → Save file to uploads/
  → asyncio.to_thread(_sync_ingest, asset)

_sync_ingest:
  → Route to extractor (PDF / DOCX / PPTX / TXT)
  → Extract raw text + [IMAGE_N] placeholders
  → Caption images (BLIP-2, optional: ENABLE_CAPTIONING=true)
  → OCR scanned pages (EasyOCR, optional: ENABLE_OCR=true)
  → Clean text (unicode, ligatures, whitespace)
  → Chunk into ~400-word segments with source metadata
  → Embed via MiniLM → upsert into ChromaDB (chroma_db/)
  → Dual-index: bge-m3 embed → ChromaDB (chroma_db_bge_comparison/)
               BM25 index rebuild in-memory
  → Return ingested chunk count
```

### Dependencies

- **No external API keys required** for basic ingestion
- `ENABLE_CAPTIONING=true` — requires BLIP-2 model (slow on CPU)
- `ENABLE_OCR=true` — requires EasyOCR + Tesseract
- `ENABLE_RETRIEVAL_PIPELINE=true` — triggers dual-index step

---

## 4. Module 3 — Course Generation

### Purpose
Convert ingested document knowledge into a structured educational course script — modules, lessons, narration scripts, slides, visuals, and quiz content. Powered by Claude.

### Entry Point
`modules/content_ingestion/course_generator.py` → `CourseGenerator.generate()`

### Main Files

| File | Role |
|------|------|
| `course_generator.py` | Three-step Claude pipeline: analyse → outline → script |
| `api/routers/courses.py` | REST endpoints, fires generation as BackgroundTask |
| `api/course_library.py` | In-memory + SQLite cache for completed scripts |
| `api/models/courses.py` | `CourseScriptRow` ORM model |
| `api/models/jobs.py` | `CourseGenerationJobRow` ORM model |

### Data Flow

```
Admin POSTs /api/v1/courses/generate
  → Create CourseGenerationJobRow (status: pending)
  → BackgroundTask: CourseGenerator.generate()

CourseGenerator.generate():
  Step 1 — _analyse()
    → Retrieve relevant chunks from ChromaDB (MiniLM)
    → Claude: identify topics, structure, target audience
  Step 2 — _outline()
    → Claude: design N modules × M lessons per module
    → _enforce_duration(): hard-clamp to chosen duration band
  Step 3 — _script_all()
    → For each lesson: Claude scripts individually
      (narration_script, bullets, key_terms, visuals,
       real_world_examples, safety_scenarios)
  → Save → CourseScriptRow in lms.db
  → course_library.add(script_id, record) → in-memory cache
  → Job status: completed

Admin polls GET /courses/jobs/{job_id}
  → Returns status + script_id when done
```

### Two Generation Modes

| Mode | Trigger | Method |
|------|---------|--------|
| **Standard** | `/courses/generate` | 3-step: analyse → outline → script each lesson |
| **Custom blueprint** | Admin provides template | Single Claude call following exact template |

### Assessment Generation

```
GET /courses/library/{id}/assessment-questions
  → Claude reads course summary + admin instructions
  → Generates MCQ + true/false questions
  → Cached in assessment_questions_json column
  → ?regenerate=true forces a fresh Claude call
```

### Dependencies

- `ANTHROPIC_API_KEY` — required
- ChromaDB (MiniLM) for chunk retrieval during scripting
- `LLM_MODEL` in config controls which Claude model is used

---

## 5. Module 4 — Retrieval Pipeline (RAG)

### Purpose
Multi-stage intelligent search over the knowledge base. Combines dense semantic search, sparse keyword search, and cross-encoder reranking to surface the most relevant chunks for AI answers.

### Entry Point
`modules/retrieval/pipeline.py` → `RetrievalPipeline.retrieve(query, source_file, history)`

### Main Files

| File | Role |
|------|------|
| `pipeline.py` | Orchestrator — runs phases 1–5 in order |
| `query_processor.py` | Claude Haiku — intent detection + contextual query rewriting |
| `bge_store.py` | ChromaDB dense search (bge-m3 embeddings) |
| `bm25_index.py` | In-memory BM25 keyword index (rebuilt on each upload) |
| `hybrid_search.py` | Dense + sparse fusion via Reciprocal Rank Fusion (RRF) |
| `reranker.py` | Cross-encoder reranker: top-30 candidates → top-8 |

### Data Flow

```
query + source_file + history
  │
  ▼ Phase 4 — Intent Detection (Claude Haiku)
  │  Detects: factual / procedural / summary / quiz / conversational
  │  Cleans ASR noise, detects language
  │  → if summary/quiz intent: skip retrieval, return empty chunks
  │
  ▼ Phase 5 — Contextual Rewrite (Claude Haiku)
  │  Resolves pronouns from conversation history
  │  e.g. "what about it?" → "what are the anchor load requirements?"
  │
  ▼ Phase 2 — Hybrid Search
  │  bge-m3 dense search  →  top-30 semantic matches
  │  BM25 keyword search  →  top-30 keyword matches
  │  RRF fusion           →  combined ranking
  │
  ▼ Phase 3 — Cross-Encoder Reranking
  │  Scores all 30 candidates against the query
  │  Returns top-8 most relevant chunks
  │
  ▼ RetrievalResult(intent, language, chunks[])
```

### Intents and Their Handling

| Intent | Action |
|--------|--------|
| `factual` | Full RAG pipeline |
| `procedural` | Full RAG pipeline |
| `conversational` | Lightweight retrieval |
| `summary` | Skip retrieval → answer from transcript |
| `quiz` | Skip retrieval → generate from lesson content |

### Dependencies

- `ANTHROPIC_API_KEY` — Claude Haiku for intent detection and rewriting
- `BAAI/bge-m3` model — downloaded automatically on first run (~2.4 GB)
- Second ChromaDB at `chroma_db_bge_comparison/`
- `ENABLE_RETRIEVAL_PIPELINE=true` in config (default: true)

---

## 6. Module 5 — AI Chat (Arresto AI)

### Purpose
Learner-facing Q&A grounded in uploaded documents and lesson transcripts. The "Arresto AI" companion panel shown inside every lesson and as a full-screen chat screen.

### Entry Point
`api/routers/chat.py` → `POST /api/v1/chat`

### Main Files

| File | Role |
|------|------|
| `api/routers/chat.py` | Route handler, intent shortcuts, context builder |
| `api/routers/voice.py` | Voice round-trip: STT → chat → TTS |

### Data Flow

```
ChatRequest
  (question + course_id + lesson_id + timestamp_secs + history[])
  │
  ▼ Load lesson narration transcript from lms.db
  │
  ▼ Intent Shortcuts (regex, no API call)
  │  "summarise this lesson"  → answer from transcript only
  │  "give me a quiz"         → generate from lesson content
  │  "explain [timestamp]"    → answer from that segment
  │
  ▼ Standard RAG Path
  │  RetrievalPipeline.retrieve()  →  intent + chunks
  │  Build context block:
  │    1. Lesson narration transcript
  │    2. Retrieved document chunks
  │    3. Last 6 turns of conversation history
  │  Claude Sonnet → answer with source citations
  │
  ▼ ChatResponse(answer, sources[])
```

### Voice Round-Trip

```
POST /api/v1/voice/chat  (audio file)
  → Sarvam STT  →  transcript text
  → _process_chat(transcript)  →  answer text
  → Sarvam TTS / edge-tts  →  MP3 audio
  → Return audio response
```

### Context Priority
1. Lesson narration transcript (from `lms.db`)
2. Retrieved document chunks (bge-m3 hybrid search)
3. Conversation history (last 6 turns)

### Dependencies

- `ANTHROPIC_API_KEY` — required
- `SARVAM_API_KEY` — required for voice mode
- RetrievalPipeline (falls back to MiniLM dense search if unavailable)

---

## 7. Module 6 — AI Tutor

### Purpose
Multi-turn, course-aware AI tutor with persistent session memory, checkpoint quiz generation, and adaptive weak-topic reinforcement. More structured than chat — knows the learner's position in the course.

### Entry Point
`modules/tutor/tutor_engine.py` → `TutorEngine.chat(session, message, store)`

### Main Files

| File | Role |
|------|------|
| `tutor_engine.py` | Chat logic, quiz generation, answer evaluation |
| `session_store.py` | In-memory + DB session persistence |
| `api/routers/tutor.py` | REST: `/session`, `/chat`, `/quiz`, `/answer` |

### Data Flow

```
POST /tutor/session
  → Create TutorSession(course_id, learner_id, module/lesson position)
  → Store in lms.db (tutor_sessions table)

POST /session/{id}/chat  (learner message)
  → Load session + history
  → RetrievalPipeline.retrieve(message, source_file, history)
  → Inject weak topics: ProgressTracker.get_weak_topic_names()
  → Build system prompt:
      - lesson content + learning objectives
      - weak topics to reinforce
      - conversation history
  → Claude Sonnet → response
  → Append to session.history → save

POST /session/{id}/quiz
  → Primary: Claude generates MCQ from lesson script
  → Fallback (no API): build MCQs from lesson bullets + key terms
  → Return questions (no correct answers shown to learner)

POST /session/{id}/answer
  → Evaluate locally (no extra API call)
  → Record result in session
```

### Adaptive Behaviour

Every `chat()` call injects the learner's current weak topics into the system prompt. If a learner scored poorly on "anchor systems", Claude automatically reinforces that topic in its next response — without the admin or learner doing anything.

### Dependencies

- `ANTHROPIC_API_KEY` — required
- `ProgressTracker` — for weak-topic injection
- `RetrievalPipeline` — for grounded answers

---

## 8. Module 7 — Video Generation

### Purpose
Render lesson narration scripts into MP4 video files. Supports two paths: a free path using Playwright + ffmpeg and a paid path using HeyGen's Video Agent API.

### Entry Point
`api/routers/video.py` → `POST /api/v1/video/generate-all/{script_id}`

### Main Files

| File | Role |
|------|------|
| `api/routers/video.py` | REST endpoints, language auto-resolution, range streaming |
| `modules/video/render_engine.py` | Dispatcher — picks TTS + renderer by style |
| `modules/video/job_store.py` | Render job persistence (lms.db + in-memory) |
| `generators/tts_router.py` | Route to Sarvam or edge-tts by language |
| `generators/sarvam_tts.py` | Sarvam Bulbul-v3 (Indian languages) |
| `generators/tts.py` | edge-tts — 70+ languages, free |
| `generators/animated_render.py` | Free renderer: Playwright → ffmpeg → MP4 |
| `generators/heygen_render.py` | Paid renderer: HeyGen Video Agent v3 |
| `generators/animated.py` | HTML scene builder for animated style |
| `generators/whiteboard.py` | HTML scene builder for whiteboard style |
| `modules/video/schemas.py` | `LessonContent`, `SlideSpec` shared dataclasses |

### Data Flow — Generate All

```
POST /video/generate-all/{script_id}?style=modern&lang=en
  │
  ▼ _resolve_lang(): "Hindi" → "hi"
  │  (auto-detects from stored course language — frontend always sends "en")
  │
  ▼ For each lesson in course:
  │   video_job_store.create(...)  →  status: pending  →  lms.db
  │   BackgroundTasks.add_task(render_lesson_in_background, job, lesson_data)
  │
  ▼ Return 202 with list of render job IDs
```

### Data Flow — Background Render

```
asyncio.to_thread(render_lesson, job, lesson)
  │
  ▼ _standard_lesson_to_content() → LessonContent + SlideSpec[]
  │
  ▼ TTS selection (tts_router.py):
  │   Indian languages (hi/ta/te/bn/gu/kn/ml/mr/pa/od)
  │     → Sarvam Bulbul-v3 (if SARVAM_API_KEY set)
  │     → edge-tts hi-IN-SwaraNeural (fallback)
  │   All other languages
  │     → edge-tts (en-US-AriaNeural, etc.)
  │   → MP3 audio saved to media/animated/{render_id}/
  │
  ▼ FREE STYLES (modern / flatcolor / whiteboard):
  │   build animated HTML scenes (CSS animations + narration text)
  │   Playwright: launch headless Chromium, record page → WebM
  │   ffmpeg: mux WebM + MP3 audio → MP4
  │   Output: media/animated/{render_id}/{lang}.mp4
  │
  ▼ HEYGEN STYLES (animated_scene / whiteboard_doodle / hybrid):
  │   Build rich prompt (scene breakdown, style guide, narration)
  │   POST /v3/video-agents → session_id
  │   Poll /v3/video-agents/{session_id} → video_id (up to 5 min)
  │   Poll /v3/videos/{video_id} → video_url (up to 40 min)
  │   Download MP4 → media/heygen/{render_id}/{lang}.mp4
  │
  ▼ job.status = "completed"
    job.video_path = absolute path to MP4
    video_job_store.save()
```

### Streaming Endpoint

```
GET /api/v1/video/renders/{render_id}/stream
  → Reads Range header from request
  → If Range: bytes=X-Y → return 206 Partial Content (seek support)
  → If no Range header   → return 200 with full file
  → Accept-Ranges: bytes header always set
```

### Job Safety

On every server startup, `VideoJobStore._load()` scans all jobs and marks any `pending` or `processing` jobs as `failed`. These jobs died in a previous process and will never complete — they are re-queued on the next `generate-all` call.

### Video Styles Summary

| Style | Renderer | Cost | TTS |
|-------|----------|------|-----|
| `modern` | Playwright + ffmpeg | Free | Sarvam / edge-tts |
| `flatcolor` | Playwright + ffmpeg | Free | Sarvam / edge-tts |
| `whiteboard` | Playwright + ffmpeg | Free | Sarvam / edge-tts |
| `animated_scene` | HeyGen Video Agent v3 | Paid per video | Built-in |
| `whiteboard_doodle` | HeyGen Video Agent v3 | Paid per video | Built-in |
| `hybrid` | HeyGen Video Agent v3 | Paid per video | Built-in |

### Dependencies

- `SARVAM_API_KEY` — Indian-language TTS narration
- `HEYGEN_API_KEY` — premium video styles only
- `ffmpeg` — must be on system PATH
- `playwright` — must be installed with Chromium (`playwright install chromium`)

---

## 9. Module 8 — Progress Tracking

### Purpose
Record every learner action, compute weak topics from quiz performance, and surface adaptive learning recommendations.

### Entry Point
`modules/progress/tracker.py` → `ProgressTracker`

### Main Files

| File | Role |
|------|------|
| `tracker.py` | Business logic: record events, compute weak topics, recommendations |
| `store.py` | SQLAlchemy CRUD operations |
| `models.py` | `LessonRecord`, `QuizAttempt`, `WeakTopic` dataclasses |
| `api/routers/progress.py` | REST endpoints for Flutter to call |

### Data Flow

```
Lesson opens
  → POST /progress/{learner}/course/{course}/lesson-start
  → LessonRecordRow created (started_at timestamp)

Video ends / KC complete
  → POST /progress/.../lesson-complete (score 0.0–1.0)
  → LessonRecordRow updated (completed_at, score)

Knowledge check answered
  → POST /progress/.../quiz-attempt
  → QuizAttemptRow saved
  → Weak topic logic:
      if accuracy < 60% across ≥ 2 attempts → WeakTopicRow created/updated

GET /progress/{learner}/course/{course}
  → LessonRecords + WeakTopics
  → Recommendations generated:
      - "Review this lesson" for score < 60%
      - "Focus on this topic" for weak topic < 60%
```

### Adaptive Learning Loop

```
WeakTopicRow (topic + accuracy)
        ↓
TutorEngine.chat() reads weak topics
        ↓
Injected into Claude system prompt
        ↓
Claude reinforces weak areas in every tutor response
```

### Dependencies

- `lms.db` only — no external APIs required

---

## 10. Module 9 — Assessments

### Purpose
End-of-course formal assessment. Admin configures questions, pass threshold, time limit, and retake count. Learners take timed quizzes and receive pass/fail with score history.

### Entry Point
`api/routers/courses.py` (config + questions) and `api/routers/assessments.py` (attempts)

### Main Files

| File | Role |
|------|------|
| `api/routers/courses.py` | Assessment config endpoints, question generation |
| `api/routers/assessments.py` | Cross-course attempt history |
| `api/models/progress.py` | `AssessmentAttemptRow` ORM model |

### Data Flow

```
Admin Configuration:
  PATCH /courses/library/{id}/assessment-config
    → num_questions, pass_pct, time_min, retakes
    → Saved to CourseScriptRow columns

Question Generation:
  GET /courses/library/{id}/assessment-questions
    → Claude reads course summary + admin instructions
    → Generates MCQ + true/false questions
    → Cached in assessment_questions_json
    → ?regenerate=true forces fresh generation

Learner Assessment:
  GET  /assessment-questions  → questions served (correct answers withheld)
  POST /assessment-attempts   → score + answers + elapsed_seconds saved
  GET  /assessment-attempts?learner_id=X  → attempt history for this course
  GET  /assessments/history?learner_id=X  → all attempts across all courses
```

### Assessment Config Defaults

| Setting | Default |
|---------|---------|
| `num_questions` | 5 |
| `pass_pct` | 70% |
| `time_min` | 30 |
| `retakes` | 3 |

### Dependencies

- `ANTHROPIC_API_KEY` — for question generation
- `lms.db` — for persistence

---

## 11. Module 10 — Analytics

### Purpose
Admin dashboard platform statistics — course counts, video counts, learner activity, and video style distribution.

### Entry Point
`api/routers/analytics.py` → `GET /api/v1/analytics/overview`

### Data Flow

```
Single SQLAlchemy session:
  COUNT(CourseScriptRow)                          → total_courses
  COUNT(VideoRenderRow WHERE status=completed)    → total_videos
  DISTINCT(LessonRecordRow.learner_id)            → total_learners
  DISTINCT(...) WHERE last_30d                    → active_learners
  GROUP BY month (last 6 months)                  → learner_activity[]
  GROUP BY style (VideoRenderRow)                 → style_distribution{}
```

### Dependencies

- `lms.db` only — no external APIs

---

## 12. Module 11 — Flutter Frontend

### Purpose
Admin and learner UI. Compiled to static web assets, served by FastAPI from `frontend-lms/build/web/`.

### Entry Point
`lib/main.dart` → `lib/core/router/router.dart`

### Main Files

| File | Role |
|------|------|
| `lib/core/router/router.dart` | GoRouter — all routes, shell wrappers, transitions |
| `lib/data/providers/api_providers.dart` | All Riverpod providers |
| `lib/core/services/api_client.dart` | Dio HTTP client (baseUrl, timeouts) |
| `lib/core/services/video_service.dart` | Video generation + render polling |
| `lib/core/services/chat_service.dart` | AI chat API |
| `lib/core/services/course_service.dart` | Course library + detail |
| `lib/core/services/progress_service.dart` | Progress recording |
| `lib/core/services/assessment_service.dart` | Quiz + attempt management |
| `lib/features/learner/lesson_player/lesson_player_screen.dart` | Core learner experience |
| `lib/features/admin/generator/generator_wizard.dart` | 9-step course creation wizard |
| `lib/features/shared/arresto_ai/arresto_ai_panel.dart` | AI chat bottom sheet |

### Route Structure

```
/admin/*                          AdminShell
  /admin                          Admin Dashboard
  /admin/generator                9-Step Course Creation Wizard
                                    Step 1: Choose source (upload / knowledge base)
                                    Step 2: Upload document
                                    Step 3: Configure course settings
                                    Step 4: Target audience
                                    Step 5: Duration + difficulty
                                    Step 6: Language
                                    Step 7: Assessment config
                                    Step 8: Generate (polls until complete)
                                    Step 9: Review + Publish
  /admin/courses                  All courses, publish controls, video status
  /admin/learners                 Learner list
  /admin/learners/:id             Learner detail + progress
  /admin/analytics                Platform stats dashboard
  /admin/settings                 API key configuration

/learner/*                        LearnerShell
  /learner                        Learner Dashboard
  /learner/catalog                Course catalog
  /learner/my-courses             Enrolled courses
  /learner/lesson/:cId/:lId       Lesson Player
                                    Real MP4 video (VideoPlayerController)
                                    Knowledge check overlay at 25%
                                    Notes + Transcript + Resources tabs
                                    Arresto AI companion panel
  /learner/assessment/:courseId   Assessment flow
    /intro                        Rules + config display
    /quiz                         Timed MCQ quiz
    /result                       Score + pass/fail
    /review                       Answer review
  /learner/assessments            All assessment history
  /learner/ai                     Arresto AI full-screen chat
  /learner/certificates           Earned certificates
  /learner/profile                Learner profile + stats
  /learner/support                Support tickets
```

### State Management

- **Riverpod** `FutureProvider.autoDispose.family` for all API calls
- `ref.listen` fires callbacks on provider state changes
- `Timer.periodic(15s)` polling for pending video renders — auto-cancels when renders complete
- `StateProvider` for learner ID and session-level state

### Video Playback Architecture

```
videoRendersProvider(courseId)
  → GET /api/v1/video/scripts/{courseId}/renders
  → Find completed render matching lesson_ref
  → Construct URL: http://localhost:8000/api/v1/video/renders/{id}/stream

_VideoBox widget:
  → VideoPlayerController.networkUrl(url)
  → Browser sends Range: bytes=X-Y for seeking
  → Backend returns 206 Partial Content
  → Real-time duration fed back to parent (_onVideoDurationLoaded)
  → Video end detected via controller listener (_onVideoEnded)
  → Lesson marked complete → progress recorded
```

### Frontend ↔ Backend API Map

| Frontend Service | Backend Router | Key Endpoints |
|-----------------|----------------|---------------|
| `CourseService` | `courses.py` | `/library`, `/generate`, `/library/{id}` |
| `VideoService` | `video.py` | `/generate-all/{id}`, `/renders/{id}`, `/stream` |
| `ChatService` | `chat.py` | `/chat` |
| `TutorService` | `tutor.py` | `/session`, `/session/{id}/chat`, `/quiz` |
| `ProgressService` | `progress.py` | `/lesson-start`, `/lesson-complete`, `/quiz-attempt` |
| `AssessmentService` | `assessments.py` | `/assessment-questions`, `/assessment-attempts` |
| `AnalyticsService` | `analytics.py` | `/overview` |
| `LearnerService` | `learners.py` | `/learners`, `/learners/{id}` |
| `DocumentService` | `documents.py` | `/upload`, `/documents` |

---

## 13. Data Storage

### SQLite — `lms.db`

| Table | Contents |
|-------|----------|
| `course_scripts` | Generated course JSON, assessment config, assessment questions |
| `course_generation_jobs` | Background job status for course generation |
| `upload_jobs` | Background job status for document uploads |
| `video_renders` | Render job status, video file path |
| `tutor_sessions` | Tutor session state + conversation history |
| `lesson_records` | Learner lesson start/complete events + score |
| `quiz_attempts` | Individual quiz question attempts |
| `weak_topics` | Aggregated weak topic scores per learner per course |
| `assessment_attempts` | End-of-course formal assessment results |
| `learner_profiles` | Learner profile data |
| `compat_ids` / `compat_counters` | Compatibility ID mapping tables |

### ChromaDB — `chroma_db/`

- MiniLM (`all-MiniLM-L6-v2`) embeddings
- Fast in-application search
- Used by: course generation (chunk retrieval), chat fallback

### ChromaDB — `chroma_db_bge_comparison/`

- bge-m3 embeddings (higher quality, ~560M params)
- Used by: primary RAG retrieval pipeline
- BM25 in-memory index rebuilt from this store on startup

### Filesystem

| Path | Contents |
|------|----------|
| `uploads/` | Raw uploaded documents (PDF, DOCX, PPTX, TXT) |
| `media/animated/{render_id}/` | Free renderer output: MP3, HTML, WebM, MP4 |
| `media/heygen/{render_id}/` | HeyGen downloaded MP4 files |
| `frontend-lms/build/web/` | Compiled Flutter web assets |

---

## 14. External Services

| Service | Purpose | Required Key | Fallback |
|---------|---------|--------------|---------|
| **Claude Sonnet 4.6** | Course generation, chat RAG, tutor, assessment questions | `ANTHROPIC_API_KEY` | None — required for AI |
| **Claude Haiku 4.5** | Intent detection, query rewriting (cheap + fast) | `ANTHROPIC_API_KEY` | Skips retrieval pipeline |
| **Sarvam Bulbul-v3** | Indian-language TTS (hi/ta/te/bn/gu/kn/ml/mr/pa/od) | `SARVAM_API_KEY` | edge-tts Indian voices |
| **Sarvam STT** | Voice-to-text transcription for voice chat | `SARVAM_API_KEY` | Voice chat disabled |
| **HeyGen Video Agent v3** | Premium animated video generation | `HEYGEN_API_KEY` | Free renderer only |
| **edge-tts (Microsoft)** | English + 70 global languages TTS | None (free) | Always available |
| **ffmpeg** | Audio concat, video compositing | System install | Render fails without it |
| **Playwright** | Record HTML animations → WebM | System install | Free video fails without it |
| **BAAI/bge-m3** | Dense embeddings for high-quality RAG | Downloaded on first run | Falls back to MiniLM |

---

## 15. Full Learner Journey

### Admin Side — Course Creation

```
1. Admin uploads PDF / DOCX to /documents/upload
   → Extracted → cleaned → chunked → embedded into ChromaDB (both stores)

2. Admin creates course at /courses/generate
   → Claude: analyse document → design outline → script each lesson
   → Course JSON saved to lms.db

3. Admin configures assessment (questions, pass%, time, retakes)
   → Claude generates MCQ/TF questions → cached

4. Admin publishes course
   → Course marked published=true
   → generate-all called → one render job per lesson created
   → Background: Sarvam TTS + Playwright + ffmpeg → MP4 per lesson
```

### Learner Side — Learning Experience

```
5. Learner opens course catalog → selects course → enters lesson

6. Lesson player loads:
   → Course detail fetched from lms.db
   → Video renders fetched → find completed render for this lesson
   → VideoPlayerController streams MP4 (HTTP 206 range requests)
   → If video still rendering: auto-polls every 15 seconds

7. During video:
   → Progress tracked (lesson-start recorded)
   → At 25% of video: knowledge check fetched from tutor engine
   → Quiz overlay shown → answers recorded → weak topics updated
   → Arresto AI panel available: RAG-grounded answers from documents

8. Video ends:
   → lesson-complete recorded with score
   → Learner moves to next lesson

9. After all lessons:
   → Assessment: timed MCQ quiz
   → Score vs pass_pct → pass/fail
   → Attempt saved → certificate unlocked if passed

10. Tutor mode (any time):
    → TutorSession created for this course
    → Every question answered with lesson context + weak topics injected
    → Claude reinforces areas where learner scored poorly
```

---

*Document generated from codebase analysis — June 2026*  
*Arresto Solutions Pvt. Ltd.*
