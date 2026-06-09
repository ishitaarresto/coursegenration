"""Pydantic schemas: API request/response + LLM structured-output shapes.

The *LLM* schemas double as the JSON Schema we hand to Claude's tool-use, so the
model is forced to return validated, schema-shaped JSON.
"""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


# ---------- API request ----------
class GenerateRequest(BaseModel):
    content_text: str = Field(..., min_length=20, description="Source content / script (source of truth)")
    mode: Literal["quick", "detailed"] = "detailed"
    languages: list[str] = Field(default_factory=lambda: ["en"])
    title_hint: str | None = None


# ---------- LLM: outline ----------
class LessonStub(BaseModel):
    title: str
    learning_objectives: list[str] = Field(default_factory=list)


class ModuleStub(BaseModel):
    title: str
    objectives: list[str] = Field(default_factory=list)
    lessons: list[LessonStub] = Field(default_factory=list)


class Outline(BaseModel):
    title: str
    description: str
    learning_objectives: list[str] = Field(default_factory=list)
    modules: list[ModuleStub] = Field(default_factory=list)


# ---------- LLM: lesson content ----------
class SafetyScenario(BaseModel):
    situation: str
    correct_action: str


class LessonContent(BaseModel):
    key_takeaways: list[str] = Field(default_factory=list)
    simplified_explanation: str = ""
    real_world_examples: list[str] = Field(default_factory=list)
    safety_scenarios: list[SafetyScenario] = Field(default_factory=list)
    summary: str = ""
    narration_script: str = ""


# ---------- LLM: slides ----------
class SlideSpec(BaseModel):
    type: Literal[
        "title", "hook", "content", "warning",
        "diagram", "comparison", "timeline", "knowledge_check", "summary"
    ] = "content"
    heading: str = ""
    bullets: list[str] = Field(default_factory=list)
    note: str = ""        # speaker note / extra context / quiz answer
    icon: str = ""        # e.g. "shield", "warning", "hardhat", "car", "road"
    diagram: str = ""     # short description of a diagram if type == diagram


class SlideDeck(BaseModel):
    slides: list[SlideSpec] = Field(default_factory=list)


# ---------- API responses ----------
class SlideOut(BaseModel):
    order: int
    type: str
    payload: dict

    class Config:
        from_attributes = True


class LessonOut(BaseModel):
    id: int
    order: int
    title: str
    learning_objectives: list[str]
    key_takeaways: list[str]
    simplified_explanation: str
    real_world_examples: list[str]
    safety_scenarios: list
    summary: str
    narration_script: str
    slides: list[SlideOut] = Field(default_factory=list)

    class Config:
        from_attributes = True


class ModuleOut(BaseModel):
    id: int
    order: int
    title: str
    objectives: list[str]
    lessons: list[LessonOut] = Field(default_factory=list)

    class Config:
        from_attributes = True


class CourseOut(BaseModel):
    id: int
    title: str
    description: str
    learning_objectives: list[str]
    mode: str
    languages: list[str]
    status: str
    modules: list[ModuleOut] = Field(default_factory=list)

    class Config:
        from_attributes = True


class JobOut(BaseModel):
    id: int
    status: str
    progress: int
    step: str
    error: str | None = None
    course_id: int | None = None

    class Config:
        from_attributes = True
