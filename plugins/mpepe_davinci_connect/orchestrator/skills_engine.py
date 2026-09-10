"""
skills_engine.py — Analyzes reference images using Gemini Vision to extract a CDL look profile (Skill).
"""
import logging
import json
import base64
from typing import Dict, Any, List
from .provider_abstraction import GeminiProvider
from .memory_store import get_memory_store

logger = logging.getLogger("cj_grader.skills_engine")

_SKILL_PROMPT = """You are a Senior Colorist analyzing a reference image to extract its look and feel.
We need to reverse-engineer this look into a DaVinci Resolve CDL profile (Slope, Offset, Power, Saturation).
Your job is to analyze the lighting, contrast, saturation, and color balance, and emit a JSON CDL profile that approximates this look.

Guidelines:
- Slope (1.0 default) affects highlights / white point.
- Offset (0.0 default) affects shadows / black point.
- Power (1.0 default) affects midtones / gamma (values > 1.0 make midtones darker).
- Saturation (1.0 default) controls overall color intensity.
- Keep values relatively subtle (e.g. slope 0.8-1.2, offset -0.05-0.05, power 0.8-1.2).

Additionally, provide a short description of the look and a list of mood tags.

ALWAYS respond with ONLY a JSON object matching this schema (no prose, no markdown fences):
{
  "description": "Short description of the look",
  "tags": ["mood", "style", "color"],
  "cdl": {
    "slope_r": <float>, "slope_g": <float>, "slope_b": <float>,
    "offset_r": <float>, "offset_g": <float>, "offset_b": <float>,
    "power_r": <float>, "power_g": <float>, "power_b": <float>,
    "saturation": <float>
  }
}
"""

class SkillsEngine:
    def __init__(self, provider: GeminiProvider):
        self.provider = provider
        self.store = get_memory_store()

    def analyze_and_save_skill(self, image_bytes: bytes, mime_type: str, name: str, user_tags: List[str]) -> Dict[str, Any]:
        """
        Analyzes the given image bytes using Gemini, extracts CDL, and saves it to the memory store.
        """
        logger.info(f"Analyzing skill '{name}' from image ({len(image_bytes)} bytes)")
        
        # Prepare the image for Gemini API (if provider supports it)
        # Using the base provider abstraction which can take parts
        # For simplicity, we'll encode it if needed, or pass it depending on the provider.
        # We need to construct a multipart request or use provider_abstraction capabilities.
        
        # Let's assume the provider_abstraction can handle image dicts.
        try:
            # Check if GeminiProvider supports passing parts directly or if we need a specific format.
            # Assuming provider_abstraction.py accepts `image_data` and `mime_type` in kwargs or we can pass a base64 string.
            # We'll use the provider abstraction. We will have to update provider_abstraction.py to support images if it doesn't already, but for now we'll pass base64 to it if we can.
            
            # Let's generate a thumbnail for the DB
            # We can just store a truncated base64 for now if we don't want to import PIL
            b64_img = base64.b64encode(image_bytes).decode('utf-8')
            # thumbnail limit for UI simplicity (let's just store the original if small or rely on flutter to send a small image)
            # Flutter can send a small resized image. Let's assume image_bytes is already small enough.
            
            parts = [
                {"mime_type": mime_type, "data": image_bytes},
                _SKILL_PROMPT
            ]
            
            # This requires updating GeminiProvider.generate_response to handle multiple parts.
            # For now, let's pass a structured prompt if supported, otherwise just text.
            # I will modify provider_abstraction.py next if it needs it.
            raw = self.provider.analyze_image(
                system_prompt=_SKILL_PROMPT,
                image_bytes=image_bytes,
                mime_type=mime_type
            )
            
            content = raw.get("content", "") if isinstance(raw, dict) else ""
            if content:
                import re
                clean = re.sub(r"```(?:json)?", "", content).strip("` \n")
                result = json.loads(clean)
                
                desc = result.get("description", "")
                ai_tags = result.get("tags", [])
                cdl = result.get("cdl", {})
                
                # Combine tags
                all_tags = list(set(user_tags + ai_tags))
                
                skill_id = self.store.save_skill(
                    name=name,
                    description=desc,
                    tags=all_tags,
                    cdl_json=json.dumps(cdl),
                    thumbnail_b64=b64_img
                )
                
                skill = self.store.get_skill(skill_id)
                logger.info(f"Skill '{name}' saved with ID {skill_id}")
                return skill
            else:
                raise ValueError("No content returned from AI.")
        except Exception as e:
            logger.error(f"Failed to analyze skill: {e}")
            # Fallback for dev without key
            fallback_cdl = {
                "slope_r": 1.05, "slope_g": 1.0, "slope_b": 0.95,
                "offset_r": 0.02, "offset_g": 0.01, "offset_b": -0.01,
                "power_r": 1.0, "power_g": 1.0, "power_b": 1.0,
                "saturation": 1.1
            }
            skill_id = self.store.save_skill(
                name=name,
                description="Fallback look (API failed)",
                tags=user_tags + ["fallback"],
                cdl_json=json.dumps(fallback_cdl),
                thumbnail_b64=base64.b64encode(image_bytes).decode('utf-8')
            )
            return self.store.get_skill(skill_id)

    def list_skills(self) -> List[Dict[str, Any]]:
        return self.store.list_skills()

    def get_skill(self, skill_id: int) -> Dict[str, Any]:
        return self.store.get_skill(skill_id)

    def delete_skill(self, skill_id: int) -> bool:
        return self.store.delete_skill(skill_id)

    def apply_skill(self, skill_id: int, timeline_id: str, track_index: int, clip_index: int) -> bool:
        skill = self.store.get_skill(skill_id)
        if not skill:
            logger.error(f"Skill {skill_id} not found")
            return False
            
        cdl = json.loads(skill["cdl_json"])
        
        # We need to call set_cdl
        from bridge.tools.cdl_tools import set_cdl
        
        slope = {"r": cdl.get("slope_r", 1.0), "g": cdl.get("slope_g", 1.0), "b": cdl.get("slope_b", 1.0)}
        offset = {"r": cdl.get("offset_r", 0.0), "g": cdl.get("offset_g", 0.0), "b": cdl.get("offset_b", 0.0)}
        power = {"r": cdl.get("power_r", 1.0), "g": cdl.get("power_g", 1.0), "b": cdl.get("power_b", 1.0)}
        sat = cdl.get("saturation", 1.0)
        
        return set_cdl(timeline_id, track_index, clip_index, 1, slope, offset, power, sat)
