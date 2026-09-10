"""
suggestion_engine.py — Analyzes frames and grading history to provide proactive suggestions.
"""
import logging
import json
from typing import Dict, Any, List
from .provider_abstraction import GeminiProvider

logger = logging.getLogger("cj_grader.suggestion_engine")

_SUGGESTION_PROMPT = """You are an expert Senior Colorist assisting a user.
You are looking at the current frame of the video, and you know the last few grading actions the user just performed.

Your job is to provide 2 or 3 short, actionable, proactive suggestions for what to do next to improve this shot.
Suggestions could be about:
- Exposure (e.g. "Shadows feel slightly crushed — try lifting offset by 0.02")
- Color balance (e.g. "Skin tones look slightly orange — apply a subtle qualifier desaturation")
- Attention / guiding the eye (e.g. "Try a subtle vignette to draw attention to the center")
- Polish (e.g. "Noise visible in dark areas — consider noise reduction")

Keep the suggestions VERY short (1 sentence max).
Also provide a "prompt" version of each suggestion — a short phrase the user could tap to execute it, as if they spoke it aloud (e.g. "add a vignette", "lift shadows").

ALWAYS respond with ONLY a JSON object matching this schema (no prose, no markdown fences):
{
  "suggestions": [
    {
      "text": "Human readable suggestion sentence",
      "prompt": "short command",
      "category": "exposure", // or "color", "skin", "noise", "creative"
      "confidence": 0.9
    }
  ]
}
"""

class SuggestionEngine:
    def __init__(self, provider: GeminiProvider):
        self.provider = provider

    def generate_suggestions(self, frame_jpeg: bytes, history_json: str, context_text: str = "") -> List[Dict[str, Any]]:
        """
        Analyzes the frame and history to generate suggestions.
        """
        if not frame_jpeg:
            logger.warning("No frame provided for suggestions")
            return []

        logger.info(f"Generating suggestions based on frame and history: {history_json[:100]}...")

        system_prompt = _SUGGESTION_PROMPT
        if history_json:
            system_prompt += f"\n\nRecent History:\n{history_json}"
        if context_text:
            system_prompt += f"\n\nLast action context:\n{context_text}"

        try:
            raw = self.provider.analyze_image(
                system_prompt=system_prompt,
                image_bytes=frame_jpeg,
                mime_type="image/jpeg"
            )
            
            content = raw.get("content", "") if isinstance(raw, dict) else ""
            if content:
                import re
                clean = re.sub(r"```(?:json)?", "", content).strip("` \n")
                result = json.loads(clean)
                return result.get("suggestions", [])
            else:
                logger.warning("No content returned for suggestions")
                return []
        except Exception as e:
            logger.error(f"Failed to generate suggestions: {e}")
            # Mock suggestions for testing without API
            return [
                {"text": "Try a subtle vignette to draw attention.", "prompt": "add a subtle vignette", "category": "creative", "confidence": 0.8},
                {"text": "Lift the shadows slightly for more detail.", "prompt": "lift the shadows", "category": "exposure", "confidence": 0.7}
            ]
