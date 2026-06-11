# Arresto LMS

AI-powered Learning Management System with course generation, video rendering, and adaptive tutoring.

## Tech stack

| Layer | Technology |
|---|---|
| Backend API | Python 3.11 · FastAPI · SQLAlchemy 2.0 |
| Frontend | Flutter (web + mobile) |
| AI | Anthropic Claude · Sarvam AI (Indian languages) |
| Vector store | ChromaDB |
| Database | SQLite (default) or PostgreSQL (production) |

---

## Quick start

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

### 2. Configure environment

```bash
cp .env.example .env
```

Open `.env` and set your `ANTHROPIC_API_KEY` at minimum. Everything else is optional for local development.

### 3. Start the server

```bash
python run_api.py
```

The server starts at `http://localhost:8000`. Interactive API docs at `http://localhost:8000/docs`.

The database (`lms.db`) is created automatically on first startup — no setup required.

---

## Database options

### SQLite (default — no installation needed)

Works out of the box. The database is stored as `lms.db` in the project root. Best for development and single-user deployments.

No changes needed — just run the server.

### PostgreSQL (recommended for production / multi-user)

**Option A — Docker (easiest)**

```bash
docker-compose up -d
```

Then uncomment and update this line in your `.env`:

```
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/arresto_lms
```

**Option B — Local PostgreSQL**

1. Install PostgreSQL 16 from https://www.postgresql.org/download/
2. Create the database:
   ```sql
   CREATE DATABASE arresto_lms;
   ```
3. Set `DATABASE_URL` in `.env`:
   ```
   DATABASE_URL=postgresql://postgres:yourpassword@localhost:5432/arresto_lms
   ```

Tables are created automatically on first startup.

---

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | — | Claude API key for AI features |
| `DATABASE_URL` | No | SQLite | PostgreSQL connection string |
| `SARVAM_API_KEY` | No | — | Indian-language TTS/STT |
| `HEYGEN_API_KEY` | No | — | Premium avatar videos |
| `TTS_PROVIDER` | No | `auto` | `auto` / `edge` / `sarvam` |
| `UPLOAD_DIR` | No | `./uploads` | Uploaded document storage |
| `CHROMA_DB_DIR` | No | `./chroma_db` | Vector store location |
| `ENABLE_OCR` | No | `false` | OCR for scanned PDFs |
| `ENABLE_CAPTIONING` | No | `false` | BLIP-2 image captioning |

See `.env.example` for the full list with descriptions.

---

## Project structure

```
LMS/
├── api/                  # FastAPI application
│   ├── main.py           # App entry point, lifespan
│   ├── db.py             # Database engine (SQLite / PostgreSQL)
│   ├── config.py         # Settings (reads from .env)
│   ├── models/           # SQLAlchemy ORM models
│   └── routers/          # API route handlers
├── modules/              # Business logic modules
│   ├── course/           # Course generation pipeline
│   ├── tutor/            # AI tutor session management
│   ├── progress/         # Learner progress tracking
│   └── video/            # Video rendering
├── LMSarresto1/          # Flutter frontend (web + mobile)
│   └── lmsarresto/
├── scripts/              # Utility / migration scripts
├── run_api.py            # Server entry point
├── requirements.txt      # Python dependencies
├── docker-compose.yml    # PostgreSQL via Docker
└── .env.example          # Environment variable template
```

---

## Running the Flutter frontend

```bash
cd LMSarresto1/lmsarresto
flutter pub get
flutter run -d chrome          # web
flutter run                    # mobile device
flutter build web --release    # production web build
```

The frontend connects to `http://localhost:8000` by default.
