"""
api/schemas.py -- All Pydantic request and response models.
"""

from __future__ import annotations
from typing import Any
from pydantic import BaseModel, Field


# -- Shared error model (used in OpenAPI responses= declarations) ---------------

class ErrorDetail(BaseModel):
    detail: str


# -- Job / background task ------------------------------------------------------

class JobStatus(BaseModel):
    job_id:                 str
    status:                 str   # pending | processing | completed | failed
    filename:               str
    error:                  str | None  = None
    chunks_created:         int | None  = None
    processing_seconds:     float | None = None


# -- Documents ------------------------------------------------------------------

class UploadResponse(BaseModel):
    job_id:         str
    filename:       str
    status:         str
    message:        str
    chunks_created: int | None = None
    document:       "DocumentContentResponse | None" = None


class BatchFileResult(BaseModel):
    filename:       str
    status:         str          # completed | failed | skipped
    chunks_created: int | None = None
    error:          str | None = None

class BatchUploadResponse(BaseModel):
    total_files:    int
    completed:      int
    failed:         int
    skipped:        int
    results:        list[BatchFileResult]
    total_chunks_stored: int

class DocumentInfo(BaseModel):
    source_file: str
    chunk_count: int
    asset_type:  str


class DocumentListResponse(BaseModel):
    documents: list[DocumentInfo]
    total:     int


class DeleteResponse(BaseModel):
    message: str


class ChunkDetail(BaseModel):
    chunk_id:        str
    chunk_index:     int
    section_heading: str | None
    page_number:     int | None
    slide_number:    int | None
    token_count:     int
    text:            str   # full chunk text


class DocumentContentResponse(BaseModel):
    source_file: str
    asset_type:  str
    total_chunks: int
    full_text:   str          # all chunks joined in order
    chunks:      list[ChunkDetail]


# -- Chat / RAG -----------------------------------------------------------------

class ChatRequest(BaseModel):
    question:           str   = Field(..., min_length=3, description="Question to ask")
    source_file:        str | None = Field(None, description="Restrict to one document")
    asset_type:         str | None = Field(None, description="pdf | docx | pptx")
    n_chunks:           int        = Field(5, ge=1, le=50)
    history:            list[dict] = Field(default_factory=list, description="Recent conversation turns [{'role': 'user'/'assistant', 'text': '...'}]")
    # Lesson context — sent from the in-lesson AI companion
    lesson_id:          str | None = Field(None, description="Lesson ID (e.g. 'm1l2')")
    course_id:          str | None = Field(None, description="Course script_id")
    timestamp_secs:     int | None = Field(None, description="Learner's current playback position")
    transcript_snippet: str | None = Field(None, description="Full narration script of the current lesson")


class SourceInfo(BaseModel):
    chunk_id:        str
    source_file:     str
    score:           float
    section_heading: str | None
    page_number:     int | None
    slide_number:    int | None
    text_preview:    str   # first 300 chars of chunk text


class ChatResponse(BaseModel):
    question:   str
    answer:     str
    sources:    list[SourceInfo]
    model_used: str | None = None


class QuestionOption(BaseModel):
    text: str

class GeneratedQuestion(BaseModel):
    type:          str              # multipleChoice | trueFalse | text
    prompt:        str
    options:       list[str]        # A/B/C/D text — empty for open-ended
    correct_index: int | None       # 0-based; None for open-ended

class QuestionGenerationRequest(BaseModel):
    course_id:      str  = Field(..., description="Course script_id")
    lesson_id:      str  = Field(..., description="Lesson ID (e.g. 'm1l2')")
    count:          int  = Field(3, ge=1, le=10)
    timestamp_secs: int | None = Field(None, description="Focus on content near this timestamp")

class QuestionGenerationResponse(BaseModel):
    lesson_title: str
    questions:    list[GeneratedQuestion]


# -- Course generation ----------------------------------------------------------

class CourseGenerateRequest(BaseModel):
    source_file:        str        = Field(..., description="Filename as stored in vector DB")
    course_title:       str | None = None
    target_audience:    str        = "learners"
    instructions:       str | None = Field(None, description="Additional instructions for the content generator (tone, focus areas, special requirements)")
    use_knowledge_base: bool       = Field(False, description="Enrich lesson context with semantically relevant chunks from all documents in the knowledge base, not just the source file")
    course_format:      str        = Field("standard", description="'standard' = auto-generated module/lesson structure; 'custom' = follow instructions as an exact blueprint (supports quizzes, specific slide counts, non-English languages, etc.)")
    language:           str        = Field("English", description="Language for all course content — e.g. 'English', 'Hindi', 'Spanish'")
    duration_range:     str        = Field("60-90 minutes", description="Target course duration: '30-45 minutes', '60-90 minutes', '2-3 hours', '3+ hours'")


class CourseGenerateResponse(BaseModel):
    job_id:  str
    status:  str
    message: str


class AssessmentConfigRequest(BaseModel):
    num_questions: int = Field(5,  ge=1, le=50,  description="Number of quiz questions")
    pass_pct:      int = Field(70, ge=1, le=100, description="Pass percentage required")
    time_min:      int = Field(30, ge=1,          description="Time limit in minutes")
    retakes:       int = Field(3,  ge=0,          description="Number of retake attempts allowed")


class PublishRequest(BaseModel):
    published:        bool = Field(True,    description="True = publish, False = revert to draft")
    publish_mode:     str  = Field("now",   description="'now' | 'draft' | 'scheduled'")
    notify_learners:  bool = Field(True)
    require_completion: bool = Field(True)
    assign_to:        str  = Field("all",   description="'all' | 'groups' | 'none'")


class CourseJobStatus(BaseModel):
    job_id:            str
    status:            str
    source_file:       str
    error:             str | None  = None
    course_script:     dict | None = None
    total_lessons:     int = 0
    completed_lessons: int = 0
    progress:          int = 0   # 0-100 percentage for the Flutter UI
    step:              str = ""  # human-readable current step for the Flutter UI


# -- AI Tutor ------------------------------------------------------------------

class TutorSessionCreateRequest(BaseModel):
    job_id:         str | None = Field(None, description="job_id from a completed POST /api/v1/courses/generate job")
    script_id:      str | None = Field(None, description="script_id from GET /api/v1/courses/library — use this when no job_id is available")
    current_module: int = Field(1, ge=1, description="Module number the learner is starting on")
    current_lesson: int = Field(1, ge=1, description="Lesson number the learner is starting on")
    learner_id:     str = Field("anonymous", description="Stable learner identifier (email, UUID, username) for progress tracking")


class TutorSessionCreateResponse(BaseModel):
    session_id:       str
    course_title:     str
    current_module:   int
    current_lesson:   int
    has_course_script: bool
    learner_id:       str
    message:          str


class TutorChatRequest(BaseModel):
    message: str = Field(..., min_length=1, description="Learner's message or question")


class TutorChatResponse(BaseModel):
    session_id:     str
    reply:          str
    history_length: int


class TutorQuizRequest(BaseModel):
    num_questions: int = Field(3, ge=1, le=10, description="Number of MCQ questions to generate")


class TutorQuizQuestion(BaseModel):
    question_id: str
    question:    str
    options:     dict[str, str]  = Field(..., description='{"A": "...", "B": "...", "C": "...", "D": "..."}')


class TutorQuizResponse(BaseModel):
    session_id:   str
    lesson_title: str
    questions:    list[TutorQuizQuestion]


class TutorAnswerRequest(BaseModel):
    question_id: str  = Field(..., description="question_id from the quiz response")
    answer:      str  = Field(..., description="Learner's chosen option: A, B, C, or D")


class TutorAnswerResponse(BaseModel):
    session_id:          str
    question_id:         str
    correct:             bool
    correct_answer:      str
    explanation:         str
    checkpoint_complete: bool         = False   # True when the last checkpoint question was just answered
    checkpoint_score:    float | None = None    # 0.0–1.0, set when checkpoint_complete is True
    checkpoint_type:     str | None   = None    # "lesson_checkpoint" | "module_checkpoint"


class TutorHistoryResponse(BaseModel):
    session_id:     str
    course_title:   str
    current_module: int
    current_lesson: int
    history:        list[dict]
    total_messages: int


# -- Checkpoint & lesson navigation --------------------------------------------

class CheckpointQuizResponse(BaseModel):
    session_id:      str
    quiz_type:       str                    # "lesson_checkpoint" | "module_checkpoint"
    lesson_title:    str
    questions:       list[TutorQuizQuestion]
    total_questions: int
    message:         str


class LessonNavigationResponse(BaseModel):
    session_id:     str
    action:         str                     # "advanced" | "module_checkpoint" | "course_complete"
    current_module: int
    current_lesson: int
    lesson_title:   str | None = None
    module_title:   str | None = None
    questions:      list[TutorQuizQuestion] | None = None   # set when action=="module_checkpoint"
    message:        str


# -- Progress & recommendations ------------------------------------------------

class LessonRecordItem(BaseModel):
    module_idx:              int
    lesson_idx:              int
    started_at:              float
    completed_at:            float | None
    checkpoint_score:        float | None
    module_checkpoint_score: float | None


class WeakTopicItem(BaseModel):
    topic:          str
    accuracy:       float
    total_attempts: int


class RecommendationItem(BaseModel):
    type:     str
    message:  str
    module:   int | None   = None
    lesson:   int | None   = None
    topic:    str | None   = None
    score:    float | None = None
    accuracy: float | None = None


class LearnerProgressResponse(BaseModel):
    learner_id:               str
    course_id:                str
    completed_lessons:        int
    average_checkpoint_score: float | None
    lesson_records:           list[LessonRecordItem]
    weak_topics:              list[WeakTopicItem]
    recommendations:          list[RecommendationItem]


# -- Audio / TTS ---------------------------------------------------------------

class AudioGenerateResponse(BaseModel):
    job_id:        str
    script_id:     str
    status:        str
    message:       str
    total_lessons: int


class AudioJobStatus(BaseModel):
    job_id:            str
    script_id:         str
    status:            str            # pending | processing | completed | failed
    total_lessons:     int
    completed_lessons: int
    errors:            list[str]


class AudioLessonInfo(BaseModel):
    module_number: int
    lesson_number: int
    filename:      str
    size_bytes:    int


class AudioListResponse(BaseModel):
    script_id:       str
    total_available: int
    lessons:         list[AudioLessonInfo]


# -- Voice Assistant -----------------------------------------------------------

class VoiceChatResponse(BaseModel):
    session_id:     str
    transcription:  str            # what Whisper heard — display in chat UI
    reply:          str            # tutor's text answer
    audio_id:       str | None     # fetch MP3 from GET /api/v1/voice/audio/{audio_id}
    history_length: int


# -- Health ---------------------------------------------------------------------

class HealthResponse(BaseModel):
    status:         str
    chunks_in_db:   int
    documents:      list[str]
    claude_enabled: bool
    captioning_on:  bool
    ocr_enabled:    bool
