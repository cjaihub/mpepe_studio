"""voice_tools — STT and TTS helpers that delegate to GeminiProvider."""
import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from orchestrator.provider_abstraction import GeminiProvider

logger = logging.getLogger("cj_grader.tools.voice")


def transcribe_audio(audio_bytes: bytes, provider: "GeminiProvider" = None, mime_type: str = "audio/wav") -> str:
    """
    Transcribes raw audio bytes to a text string.

    Uses GeminiProvider.transcribe if a provider is passed (preferred path).
    Falls back to SpeechRecognition + Google free web API if provider is None.

    Returns the transcript string, or empty string on failure.
    """
    if provider is not None:
        try:
            return provider.transcribe(audio_bytes, mime_type=mime_type)
        except Exception as e:
            logger.error(f"provider.transcribe failed: {e} — trying SpeechRecognition")

    # Standalone fallback (no provider injected)
    try:
        import speech_recognition as sr
        import io

        recognizer = sr.Recognizer()
        with sr.AudioFile(io.BytesIO(audio_bytes)) as source:
            audio = recognizer.record(source)
        text = recognizer.recognize_google(audio)
        logger.info(f"STT transcript: '{text}'")
        return text
    except ImportError:
        logger.error("SpeechRecognition not installed. Run: pip install SpeechRecognition pyaudio")
        return ""
    except Exception as e:
        logger.error(f"STT fallback failed: {e}")
        return ""


def synthesize_speech(text: str, provider: "GeminiProvider" = None) -> bytes:
    """
    Converts a text string to WAV audio bytes.

    Uses GeminiProvider.speak if a provider is passed (preferred path).
    Falls back to pyttsx3 (fully offline) if provider is None.

    Returns raw WAV bytes, or empty bytes on failure.
    """
    if provider is not None:
        try:
            return provider.speak(text)
        except Exception as e:
            logger.error(f"provider.speak failed: {e} — trying pyttsx3")

    # Standalone fallback
    try:
        import pyttsx3
        import tempfile
        import os

        engine = pyttsx3.init()
        engine.setProperty("rate", 165)
        engine.setProperty("volume", 1.0)

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            tmp_path = f.name

        engine.save_to_file(text, tmp_path)
        engine.runAndWait()

        with open(tmp_path, "rb") as f:
            audio_bytes = f.read()
        os.unlink(tmp_path)
        return audio_bytes
    except ImportError:
        logger.error("pyttsx3 not installed. Run: pip install pyttsx3")
        return b""
    except Exception as e:
        logger.error(f"TTS fallback failed: {e}")
        return b""
