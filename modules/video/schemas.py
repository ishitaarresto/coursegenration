"""Minimal dataclasses mirroring LMSarresto's LessonContent / SlideSpec shapes.

These are used as duck-type-compatible inputs to the animated.py scene builder.
Python does not enforce type hints at runtime, so plain dataclasses work as
drop-in replacements for the Pydantic models in the original codebase.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class SlideSpec:
    type: str = "content"           # title | hook | content | warning | diagram | summary
    heading: str = ""
    bullets: list[str] = field(default_factory=list)
    note: str = ""                  # speaker note / extra context
    icon: str = ""                  # e.g. "shield", "warning", "hardhat", "book"
    diagram: str = ""               # short diagram description (type=="diagram" only)


@dataclass
class SafetyScenario:
    situation: str = ""
    correct_action: str = ""


@dataclass
class LessonContent:
    narration_script: str = ""
    key_takeaways: list[str] = field(default_factory=list)
    simplified_explanation: str = ""
    real_world_examples: list[str] = field(default_factory=list)
    safety_scenarios: list[SafetyScenario] = field(default_factory=list)
    summary: str = ""
