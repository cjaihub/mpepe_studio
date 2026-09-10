import os
import requests
import logging
from typing import List, Dict, Any

logger = logging.getLogger("cj_grader.provider")

class GeminiProvider:
    def __init__(self, api_key: str = None, proxy_url: str = None):
        self.api_key = api_key or os.environ.get("GEMINI_API_KEY")
        self.proxy_url = proxy_url
        if not self.api_key and not self.proxy_url:
            logger.warning("No Gemini API key or proxy URL provided.")
            
    def generate_response(self, system_prompt: str, user_prompt: str, tools: List[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Calls the Gemini model (either directly or via proxy)."""
        logger.info("Generating response from Gemini...")
        if self.proxy_url:
            # Use Firebase Cloud Function proxy
            try:
                response = requests.post(
                    self.proxy_url, 
                    json={"system": system_prompt, "prompt": user_prompt, "tools": tools}
                )
                response.raise_for_status()
                return response.json()
            except Exception as e:
                logger.error(f"Error calling Gemini Proxy: {e}")
                return {"error": str(e)}
        elif self.api_key:
            # Direct Gemini SDK call
            try:
                import google.generativeai as genai
                genai.configure(api_key=self.api_key)
                model = genai.GenerativeModel(
                    model_name="gemini-1.5-flash",
                    system_instruction=system_prompt,
                )
                result = model.generate_content(user_prompt)
                content = result.text if hasattr(result, "text") else ""
                logger.info(f"Gemini responded ({len(content)} chars)")
                return {"role": "assistant", "content": content}
            except ImportError:
                logger.error("google-generativeai not installed. Run: pip install google-generativeai")
                return {"role": "assistant", "content": ""}
            except Exception as e:
                logger.error(f"Gemini SDK call failed: {e}")
                return {"error": str(e), "content": ""}
        else:
            # No key and no proxy — return empty so director falls back to demo plan
            logger.warning("No API key or proxy — falling back to demo plan")
            return {"role": "assistant", "content": ""}

    def chat(self, system_prompt: str, history: List[Dict[str, str]], user_prompt: str) -> str:
        """Conversational chat that maintains history."""
        logger.info("Generating chat response from Gemini...")
        if self.api_key:
            try:
                import google.generativeai as genai
                genai.configure(api_key=self.api_key)
                model = genai.GenerativeModel(
                    model_name="gemini-1.5-flash",
                    system_instruction=system_prompt,
                )
                
                # Convert history to genai format
                formatted_history = []
                for msg in history:
                    formatted_history.append({
                        "role": "model" if msg["role"] == "assistant" else "user",
                        "parts": [msg["content"]]
                    })
                    
                chat_session = model.start_chat(history=formatted_history)
                result = chat_session.send_message(user_prompt)
                content = result.text if hasattr(result, "text") else ""
                return content
            except ImportError:
                logger.error("google-generativeai not installed.")
                return ""
            except Exception as e:
                logger.error(f"Gemini chat failed: {e}")
                return ""
        else:
            return "I'm running in offline mode without an API key. I can still grade clips, but I can't hold a natural conversation!"

    def analyze_image(self, system_prompt: str, image_bytes: bytes, mime_type: str = "image/jpeg") -> Dict[str, Any]:
        """Calls the Gemini Vision model to analyze an image."""
        logger.info("Generating vision response from Gemini...")
        import base64
        base64_image = base64.b64encode(image_bytes).decode('utf-8')
        
        if self.proxy_url:
            try:
                response = requests.post(
                    self.proxy_url, 
                    json={
                        "system": system_prompt, 
                        "prompt": "Analyze this reference image.", 
                        "image": {
                            "data": base64_image,
                            "mime_type": mime_type
                        }
                    }
                )
                response.raise_for_status()
                return response.json()
            except Exception as e:
                logger.error(f"Error calling Gemini Proxy: {e}")
                return {"error": str(e)}
        elif self.api_key:
            try:
                import google.generativeai as genai
                from google.generativeai.types import Part
                genai.configure(api_key=self.api_key)
                model = genai.GenerativeModel("gemini-1.5-flash")
                image_part = Part.from_data(data=image_bytes, mime_type=mime_type)
                result = model.generate_content([system_prompt, image_part])
                return {"role": "assistant", "content": result.text if hasattr(result, "text") else ""}
            except ImportError:
                logger.error("google-generativeai not installed.")
                return {"role": "assistant", "content": '{"status": "error", "message": "google-generativeai not installed"}'}
            except Exception as e:
                logger.error(f"Gemini vision call failed: {e}")
                return {"error": str(e)}
        else:
            return {"role": "assistant", "content": '{"status": "success", "look": {"description": "mocked vision", "cdl": {"slope_r": 1.0, "slope_g": 1.0, "slope_b": 1.0, "offset_r": 0.0, "offset_g": 0.0, "offset_b": 0.0, "power_r": 1.0, "power_g": 1.0, "power_b": 1.0, "saturation": 1.0}}}'}

    def transcribe(self, audio_bytes: bytes, mime_type: str = "audio/wav") -> str:
        """
        Transcribes audio to text.
        Uses Gemini multimodal if API key is set, otherwise falls back to
        SpeechRecognition (Google free web API, internet required).
        """
        if self.api_key:
            try:
                import google.generativeai as genai
                from google.generativeai.types import Part
                genai.configure(api_key=self.api_key)
                model = genai.GenerativeModel("gemini-1.5-flash")
                audio_part = Part.from_data(data=audio_bytes, mime_type=mime_type)
                result = model.generate_content(
                    ["Transcribe this audio exactly as spoken. Return only the transcript, no explanation.", audio_part]
                )
                return result.text.strip() if hasattr(result, "text") else ""
            except Exception as e:
                logger.error(f"Gemini STT failed: {e} — falling back to SpeechRecognition")

        # Offline fallback via SpeechRecognition
        try:
            import speech_recognition as sr
            import io
            recognizer = sr.Recognizer()
            with sr.AudioFile(io.BytesIO(audio_bytes)) as source:
                audio = recognizer.record(source)
            text = recognizer.recognize_google(audio)
            logger.info(f"SpeechRecognition transcript: {text}")
            return text
        except ImportError:
            logger.error("SpeechRecognition not installed. Run: pip install SpeechRecognition")
            return ""
        except Exception as e:
            logger.error(f"SpeechRecognition failed: {e}")
            return ""

    def speak(self, text: str) -> bytes:
        """
        Synthesizes text to speech audio bytes (WAV).
        Falls back to pyttsx3 for fully offline TTS.
        """
        try:
            import pyttsx3
            import io
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
            logger.error(f"TTS synthesis failed: {e}")
            return b""
