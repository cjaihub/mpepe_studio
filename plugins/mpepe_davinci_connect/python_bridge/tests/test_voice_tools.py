"""
Tests for voice_tools.py — exercises transcribe_audio and synthesize_speech
with a mocked provider so no real API calls or microphone are needed.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))


class _MockProvider:
    """Minimal provider stub that returns predictable values."""

    def transcribe(self, audio_bytes: bytes, mime_type: str = "audio/wav") -> str:
        return "cool the shadows"

    def speak(self, text: str) -> bytes:
        return b"MOCK_WAV_BYTES"


def test_transcribe_audio_with_provider():
    from bridge.tools.voice_tools import transcribe_audio

    result = transcribe_audio(b"\x00" * 64, provider=_MockProvider())
    assert result == "cool the shadows", f"Expected 'cool the shadows', got '{result}'"


def test_synthesize_speech_with_provider():
    from bridge.tools.voice_tools import synthesize_speech

    result = synthesize_speech("Applied CDL", provider=_MockProvider())
    assert result == b"MOCK_WAV_BYTES"


def test_transcribe_audio_no_provider_returns_str():
    """Without a provider, transcribe_audio should return a str (possibly empty)."""
    from bridge.tools.voice_tools import transcribe_audio

    result = transcribe_audio(b"\x00" * 64, provider=None)
    assert isinstance(result, str)


def test_synthesize_speech_no_provider_returns_bytes():
    """Without a provider, synthesize_speech should return bytes (possibly empty)."""
    from bridge.tools.voice_tools import synthesize_speech

    result = synthesize_speech("hello", provider=None)
    assert isinstance(result, (bytes, bytearray))
