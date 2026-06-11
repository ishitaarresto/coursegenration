"""
api/routers/documents.py

POST   /api/v1/documents/upload                  Upload & ingest a new file
POST   /api/v1/documents/batch-upload            Upload & ingest multiple files
POST   /api/v1/documents/ingest/{filename}       Ingest a file already in uploads/
GET    /api/v1/documents/available               List files in uploads/ with ingestion status
GET    /api/v1/documents                         List all ingested documents
GET    /api/v1/documents/jobs/{id}               Get job status
GET    /api/v1/documents/{filename}/content      Read extracted chunks for a document
DELETE /api/v1/documents/{filename}              Remove a document from both vector stores
"""

import asyncio
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File

from api.config import settings
from api.dependencies import (
    get_pipeline, get_retrieval_pipeline, get_vector_store,
    _sync_ingest,
    job_store,
)
from api.schemas import (
    BatchFileResult, BatchUploadResponse,
    ChunkDetail, DeleteResponse, DocumentContentResponse,
    DocumentInfo, DocumentListResponse,
    JobStatus, UploadResponse,
)

router = APIRouter(prefix="/api/v1/documents", tags=["Documents"])

_SUPPORTED = {".pdf", ".docx", ".pptx"}


def _build_content(filename: str, vector_store) -> DocumentContentResponse:
    """Read all chunks for a filename from the store and build the response."""
    chunks = vector_store.get_all_by_source(filename)
    asset_type = chunks[0]["metadata"].get("asset_type", "unknown") if chunks else "unknown"
    details = [
        ChunkDetail(
            chunk_id=c["chunk_id"],
            chunk_index=c["metadata"].get("chunk_index", i),
            section_heading=c["metadata"].get("section_heading") or None,
            page_number=(
                c["metadata"]["page_number"]
                if c["metadata"].get("page_number", -1) > 0 else None
            ),
            slide_number=(
                c["metadata"]["slide_number"]
                if c["metadata"].get("slide_number", -1) > 0 else None
            ),
            token_count=c["metadata"].get("token_count", 0),
            text=c["text"],
        )
        for i, c in enumerate(chunks)
    ]
    return DocumentContentResponse(
        source_file=filename,
        asset_type=asset_type,
        total_chunks=len(details),
        full_text="\n\n".join(d.text for d in details),
        chunks=details,
    )


@router.post("/upload", response_model=UploadResponse)
async def upload_document(
    file:               UploadFile = File(...),
    pipeline=Depends(get_pipeline),
    vector_store=Depends(get_vector_store),
    retrieval_pipeline=Depends(get_retrieval_pipeline),
):
    """
    Upload a PDF, DOCX, or PPTX file.

    Processing runs **synchronously** — the response is returned only after
    extraction, cleaning, chunking, embedding into both vector stores
    (MiniLM + bge-m3), and BM25 index rebuild are all complete.
    The response body includes the full extracted text and every chunk so you
    can immediately verify what was captured.
    """
    ext = Path(file.filename).suffix.lower()
    if ext not in _SUPPORTED:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{ext}'. Supported: {sorted(_SUPPORTED)}",
        )

    dest = settings.upload_dir / file.filename
    raw  = await file.read()
    dest.write_bytes(raw)

    job = job_store.create_upload(file.filename)
    await asyncio.to_thread(_sync_ingest, job, dest, pipeline, retrieval_pipeline)

    if job.status == "failed":
        raise HTTPException(status_code=500, detail=f"Ingestion failed: {job.error}")

    doc = _build_content(file.filename, vector_store)

    return UploadResponse(
        job_id=job.job_id,
        filename=file.filename,
        status="completed",
        message=f"'{file.filename}' ingested — {job.chunks_created} chunks stored.",
        chunks_created=job.chunks_created,
        document=doc,
    )


@router.post("/batch-upload", response_model=BatchUploadResponse)
async def batch_upload_documents(
    files:    Annotated[list[UploadFile], File(description="Select multiple PDF / DOCX / PPTX files")],
    pipeline=Depends(get_pipeline),
    vector_store=Depends(get_vector_store),
    retrieval_pipeline=Depends(get_retrieval_pipeline),
):
    """
    Upload and ingest multiple files (PDF, DOCX, PPTX) in one request.

    Files are processed **sequentially** — one fully completes before the next
    starts. This keeps memory usage predictable and avoids loading multiple
    ML models in parallel.

    Each file in `results` shows status, chunks created, or an error message.
    The overall response is returned only after ALL files finish.

    Swagger: click 'Try it out', then click the 'Add item' button under
    `files` to add more files before hitting Execute.
    """
    results: list[BatchFileResult] = []
    total_chunks = 0

    for file in files:
        ext = Path(file.filename).suffix.lower()
        if ext not in _SUPPORTED:
            results.append(BatchFileResult(
                filename=file.filename,
                status="skipped",
                error=f"Unsupported type '{ext}'. Supported: {sorted(_SUPPORTED)}",
            ))
            continue

        dest = settings.upload_dir / file.filename
        raw  = await file.read()
        dest.write_bytes(raw)

        job = job_store.create_upload(file.filename)
        await asyncio.to_thread(_sync_ingest, job, dest, pipeline, retrieval_pipeline)

        if job.status == "completed":
            total_chunks += job.chunks_created or 0
            results.append(BatchFileResult(
                filename=file.filename,
                status="completed",
                chunks_created=job.chunks_created,
            ))
        else:
            results.append(BatchFileResult(
                filename=file.filename,
                status="failed",
                error=job.error,
            ))

    completed = sum(1 for r in results if r.status == "completed")
    failed    = sum(1 for r in results if r.status == "failed")
    skipped   = sum(1 for r in results if r.status == "skipped")

    return BatchUploadResponse(
        total_files=len(files),
        completed=completed,
        failed=failed,
        skipped=skipped,
        results=results,
        total_chunks_stored=total_chunks,
    )


@router.get("/jobs/{job_id}", response_model=JobStatus)
def get_upload_job(job_id: str):
    """Poll the status of an upload/ingestion job."""
    job = job_store.get_upload(job_id)
    if not job:
        raise HTTPException(status_code=404, detail=f"Job '{job_id}' not found.")
    return job.to_schema()


@router.get("", response_model=DocumentListResponse)
def list_documents(vector_store=Depends(get_vector_store)):
    """Return all documents currently stored in the vector database."""
    sources = vector_store.list_sources()
    docs: list[DocumentInfo] = []
    for sf in sources:
        chunks = vector_store.get_all_by_source(sf)
        asset_type = chunks[0]["metadata"].get("asset_type", "unknown") if chunks else "unknown"
        docs.append(DocumentInfo(
            source_file=sf,
            chunk_count=len(chunks),
            asset_type=asset_type,
        ))
    return DocumentListResponse(documents=docs, total=len(docs))


@router.get("/{filename}/content", response_model=DocumentContentResponse)
def get_document_content(filename: str, vector_store=Depends(get_vector_store)):
    """
    Return the full extracted text for a document, split into chunks.

    This is what was actually stored in the knowledge base after
    extraction -> cleaning -> chunking.  Use it to verify that the right
    content was captured before running chat or course generation.

    Each chunk shows:
    - **chunk_index** -- position in the document
    - **section_heading** -- nearest heading above this chunk
    - **page_number / slide_number** -- provenance
    - **text** -- the exact text that will be used for RAG retrieval
    """
    chunks = vector_store.get_all_by_source(filename)
    if not chunks:
        raise HTTPException(
            status_code=404,
            detail=f"No document named '{filename}' found. Upload it first.",
        )

    asset_type = chunks[0]["metadata"].get("asset_type", "unknown")
    chunk_details = [
        ChunkDetail(
            chunk_id=c["chunk_id"],
            chunk_index=c["metadata"].get("chunk_index", i),
            section_heading=c["metadata"].get("section_heading") or None,
            page_number=(
                c["metadata"]["page_number"]
                if c["metadata"].get("page_number", -1) > 0 else None
            ),
            slide_number=(
                c["metadata"]["slide_number"]
                if c["metadata"].get("slide_number", -1) > 0 else None
            ),
            token_count=c["metadata"].get("token_count", 0),
            text=c["text"],
        )
        for i, c in enumerate(chunks)
    ]
    full_text = "\n\n".join(cd.text for cd in chunk_details)

    return DocumentContentResponse(
        source_file=filename,
        asset_type=asset_type,
        total_chunks=len(chunk_details),
        full_text=full_text,
        chunks=chunk_details,
    )


@router.get("/available")
def list_available_files(vector_store=Depends(get_vector_store)):
    """
    List every supported file in the uploads/ directory with its ingestion status.

    Use this to discover files that are already on disk and can be ingested
    without re-uploading — then call **POST /api/v1/documents/ingest/{filename}**
    to ingest any file whose `ingested` field is false.
    """
    ingested = set(vector_store.list_sources())
    files = []
    for f in sorted(settings.upload_dir.iterdir()):
        if f.is_file() and f.suffix.lower() in _SUPPORTED:
            files.append({
                "filename":   f.name,
                "size_bytes": f.stat().st_size,
                "ingested":   f.name in ingested,
            })
    return {"files": files, "total": len(files)}


@router.post("/ingest/{filename}", response_model=UploadResponse)
async def ingest_existing_file(
    filename:           str,
    pipeline=Depends(get_pipeline),
    vector_store=Depends(get_vector_store),
    retrieval_pipeline=Depends(get_retrieval_pipeline),
):
    """
    Ingest a file that already exists in the uploads/ directory.

    Use **GET /api/v1/documents/available** first to see which files are on disk.
    This is the fast path — no re-uploading needed, just trigger processing.

    Safe to re-run: existing chunks are overwritten (upsert), not duplicated.
    """
    file_path = settings.upload_dir / filename
    if not file_path.exists():
        raise HTTPException(
            status_code=404,
            detail=(
                f"'{filename}' not found in uploads/. "
                "Upload it first via POST /api/v1/documents/upload."
            ),
        )

    ext = file_path.suffix.lower()
    if ext not in _SUPPORTED:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{ext}'. Supported: {sorted(_SUPPORTED)}",
        )

    job = job_store.create_upload(filename)
    await asyncio.to_thread(_sync_ingest, job, file_path, pipeline, retrieval_pipeline)

    if job.status == "failed":
        raise HTTPException(status_code=500, detail=f"Ingestion failed: {job.error}")

    doc = _build_content(filename, vector_store)

    return UploadResponse(
        job_id=job.job_id,
        filename=filename,
        status="completed",
        message=f"'{filename}' ingested — {job.chunks_created} chunks stored.",
        chunks_created=job.chunks_created,
        document=doc,
    )


@router.delete("/{filename}", response_model=DeleteResponse)
def delete_document(
    filename:           str,
    vector_store=Depends(get_vector_store),
    retrieval_pipeline=Depends(get_retrieval_pipeline),
):
    """Remove all chunks for a document from both vector stores (MiniLM + bge-m3)."""
    chunks = vector_store.get_all_by_source(filename)
    if not chunks:
        raise HTTPException(
            status_code=404,
            detail=f"No document named '{filename}' found in the store.",
        )
    vector_store.delete_by_source(filename)

    if retrieval_pipeline is not None:
        try:
            retrieval_pipeline.delete_source(filename)
        except Exception as exc:
            print(f"[bge_index] WARNING: BGE delete failed: {exc}")

    upload_path = settings.upload_dir / filename
    if upload_path.exists():
        upload_path.unlink()

    return DeleteResponse(message=f"'{filename}' removed ({len(chunks)} chunks deleted).")
