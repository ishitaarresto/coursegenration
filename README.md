# Arresto LMS

AI-powered Learning Management System with course generation, video rendering, and adaptive tutoring.

## Tech stack

| Layer | Technology |
|---|---|
| Backend API | Python 3.11 · FastAPI · SQLAlchemy 2.0 |
| Frontend | Flutter (web + mobile) |
| AI | Anthropic Claude · Sarvam AI (Indian languages) · HeyGen (avatar video) |
| Vector store | ChromaDB (MiniLM + BGE-M3 dual-index) |
| Database | PostgreSQL (production) · SQLite (dev fallback) |
| Containerisation | Docker · AWS ECS Fargate |

---

## Quick start (local dev)

### 1. Clone and set up Python environment

```bash
git clone <your-repo-url>
cd LMS

python -m venv .venv

# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

pip install -r requirements.txt
```

### 2. Start PostgreSQL

```bash
docker-compose up -d postgres
```

### 3. Configure environment

```bash
cp .env.example .env
```

Open `.env` and set at minimum:

```
ANTHROPIC_API_KEY=sk-ant-...
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/arresto_lms
```

All tables are created automatically on first startup.

### 4. Start the backend

```powershell
# Windows (opens two windows — backend + Flutter dev server):
.\start.ps1

# Or start the backend only:
.venv\Scripts\uvicorn.exe api.main:app --host 0.0.0.0 --port 8000 --reload
```

Backend: `http://localhost:8000`  
API docs: `http://localhost:8000/docs`

### 5. Start the Flutter frontend (separate terminal)

```bash
cd frontend-lms
flutter pub get
flutter run -d web-server --web-port 5500 --web-hostname localhost
```

Frontend: `http://localhost:5500`

---

## Database

PostgreSQL is the default database. Start it with Docker before running the server:

```bash
docker-compose up -d postgres
```

The default connection string (used when `DATABASE_URL` is not set):

```
postgresql://postgres:postgres@localhost:5432/arresto_lms
```

Tables are created automatically on first startup.

**Local PostgreSQL install:** Install PostgreSQL 16, create the `arresto_lms` database, then set `DATABASE_URL` in `.env` to match your credentials.

### SQLite (dev-only fallback)

Set `DATABASE_URL=sqlite:///./lms.db` in `.env` to use SQLite instead. Not recommended — data is lost on container restart and does not support concurrent writes.

---

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | — | Claude API key (course gen, chat, tutor) |
| `DATABASE_URL` | No | SQLite | PostgreSQL connection string |
| `PROGRESS_DB_PATH` | No | `lms.db` | SQLite path for learner progress tracking. Use `/tmp/lms.db` in containers or an EFS path for persistence |
| `CORS_ORIGINS` | No | `*` | Allowed CORS origins. Comma-separated in production: `https://yourdomain.com` |
| `LLM_MODEL` | No | `claude-sonnet-4-6` | Claude model for course generation and chat |
| `SARVAM_API_KEY` | No | — | Indian-language TTS + STT |
| `SARVAM_LANGUAGE` | No | `en-IN` | Default language for Sarvam TTS |
| `HEYGEN_API_KEY` | No | — | Premium avatar video rendering |
| `TTS_PROVIDER` | No | `auto` | `auto` / `edge` / `sarvam` |
| `UPLOAD_DIR` | No | `./uploads` | Document + audio cache storage |
| `CHROMA_DB_DIR` | No | `./chroma_db` | Vector store (MiniLM) location |
| `ENABLE_OCR` | No | `false` | EasyOCR for scanned PDFs |
| `ENABLE_CAPTIONING` | No | `false` | BLIP-2 image captioning (very slow on CPU) |

See `.env.example` for the full list with descriptions.

---

## Project structure

```
LMS/
├── api/                      # FastAPI application
│   ├── main.py               # App entry point + lifespan
│   ├── db.py                 # Database engine (PostgreSQL / SQLite)
│   ├── config.py             # All settings (reads from .env)
│   ├── course_library.py     # Course persistence (PostgreSQL via SQLAlchemy)
│   ├── models/               # SQLAlchemy ORM models
│   └── routers/              # 57 API endpoints across 13 domains
├── modules/                  # Business logic
│   ├── content_ingestion/    # PDF/DOCX/PPTX extraction + embedding pipeline
│   ├── retrieval/            # BGE-M3 + BM25 + reranker retrieval pipeline
│   ├── tutor/                # AI tutor session engine
│   ├── progress/             # Learner progress tracking (SQLite-backed)
│   ├── video/                # Video rendering + TTS engines
│   └── voice/                # Sarvam STT transcription
├── frontend-lms/             # Flutter frontend (web + mobile)
│   └── lib/
│       └── core/config/
│           └── api_config.dart   # API base URL (set via --dart-define)
├── deploy/                   # AWS deployment configs
│   ├── ecs-task-definition.json  # ECS Fargate task definition template
│   └── buildspec.yml             # AWS CodeBuild: Flutter build → Docker → ECR
├── Dockerfile                # Backend container image
├── docker-compose.yml        # Local dev: PostgreSQL + backend app
├── start.ps1                 # Windows dev launcher (backend + Flutter)
├── requirements.txt          # Python dependencies
└── .env.example              # Environment variable template
```

---

## Running with Docker (full stack)

Build the Flutter web app first, then build and run the container:

```bash
# 1. Build Flutter web
cd frontend-lms
flutter build web --dart-define=API_BASE_URL=http://localhost:8000
cd ..

# 2. Start everything
docker-compose up --build
```

Backend + frontend served at `http://localhost:8000`.

---

## AWS deployment

### Architecture

```
Internet → ALB → ECS Fargate (Docker container)
                      ↓               ↓
                 RDS PostgreSQL    EFS (uploads + ChromaDB)
                 Secrets Manager   ECR (Docker images)
                 CloudWatch Logs
```

### Required AWS resources

| Resource | Purpose |
|---|---|
| **ECR** | Docker image registry |
| **ECS Fargate** | Run the container (2 vCPU / 4 GB) |
| **RDS PostgreSQL 16** | Production database |
| **EFS** | Persistent storage for uploads and ChromaDB |
| **Secrets Manager** | API keys at runtime |
| **ALB** | Load balancer; health check at `/health` |
| **CodeBuild** | CI/CD: Flutter build → Docker push to ECR |

### Secrets to create in AWS Secrets Manager

```
arresto/DATABASE_URL        → postgresql://user:pass@rds-host:5432/arresto_lms
arresto/ANTHROPIC_API_KEY   → sk-ant-...
arresto/HEYGEN_API_KEY      → sk_V2_...
arresto/SARVAM_API_KEY      → sk_...
```

### ECS task definition

Edit `deploy/ecs-task-definition.json` and replace:

| Placeholder | Replace with |
|---|---|
| `ACCOUNT_ID` | Your 12-digit AWS account number |
| `REGION` | e.g. `ap-south-1` |
| `fs-XXXXXXXX` | Your EFS file system ID |

### CodeBuild environment variables

Set these in your CodeBuild project:

```
AWS_ACCOUNT_ID   = 123456789012
AWS_DEFAULT_REGION = ap-south-1
ECR_REPO_NAME    = arresto-lms
API_BASE_URL     = https://your-backend-domain.com
```

### IAM roles needed

**`ecsTaskExecutionRole`** (AWS creates this automatically):
- `AmazonECSTaskExecutionRolePolicy`
- `secretsmanager:GetSecretValue` on your `arresto/*` secrets

**`arresto-lms-task-role`** (create manually):
- `CloudWatchLogsFullAccess`
- `AmazonElasticFileSystemClientFullAccess`

### Flutter frontend API URL

The backend URL is injected at build time via `--dart-define`:

```bash
flutter build web --dart-define=API_BASE_URL=https://your-backend-domain.com --release
```

This is handled automatically by `deploy/buildspec.yml` using the `API_BASE_URL` CodeBuild variable.

---

## API overview

57 endpoints across 13 domains. Full interactive docs at `/docs`.

| Domain | Prefix | Key endpoints |
|---|---|---|
| Documents | `/api/v1/documents` | Upload, ingest, list, delete |
| Courses | `/api/v1/courses` | Generate, library, publish, assessments |
| Video | `/api/v1/video` | Render, stream, download, generate-all |
| Audio | `/api/v1/audio` | Stream lesson MP3, pre-warm cache |
| AI Chat | `/api/v1/chat` | RAG Q&A with citations |
| AI Tutor | `/api/v1/tutor` | Session-based adaptive tutor + checkpoints |
| Voice | `/api/v1/voice` | Voice round-trip (STT → Claude → TTS) |
| Questions | `/api/v1/questions` | Generate MCQ/T-F from lesson at timestamp |
| Progress | `/api/v1/progress` | Lesson tracking, quiz attempts, recommendations |
| Assessments | `/api/v1/assessments` | Cross-course attempt history |
| Learners | `/api/v1/learners` | Admin learner management |
| Profile | `/api/v1/profile` | Learner profile + stats |
| Analytics | `/api/v1/analytics` | Platform-wide overview |
| Notifications | `/api/v1/notifications` | In-app notifications |
