# Arresto LMS — Backend container
#
# Before building, compile the Flutter web app:
#   cd frontend-lms
#   flutter build web --dart-define=API_BASE_URL=https://your-backend-url.com
#   cd ..
#
# Build:   docker build -t arresto-lms .
# Run:     docker run -p 8000:8000 --env-file .env arresto-lms

FROM python:3.11-slim

WORKDIR /app

# System libraries required by easyocr / PyMuPDF / OpenCV
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxrender1 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (layer-cached until requirements.txt changes)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY api/        ./api/
COPY modules/    ./modules/

# Copy pre-built Flutter web output (built outside Docker in CI)
COPY frontend-lms/build/web/ ./frontend-lms/build/web/

# Persistent data directories — mount EFS or a volume here in production
RUN mkdir -p /data/uploads /data/chroma_db /tmp

EXPOSE 8000

CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
