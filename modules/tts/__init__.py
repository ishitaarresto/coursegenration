"""
modules/tts -- Text-to-Speech synthesis for lesson narration audio.

Public surface:
  TTSEngine -- wraps OpenAI TTS API, handles long text splitting + MP3 output
"""

from modules.tts.tts_engine import TTSEngine

__all__ = ["TTSEngine"]
