import logging
import json
import re
from .provider_abstraction import GeminiProvider

logger = logging.getLogger("cj_grader.director")

_SYSTEM_PROMPT = """You are the Director Agent for CJ Grader, an expert Senior Colorist and DIT for DaVinci Resolve.

Your job is to translate the user's natural-language grading request into a precise, executable step-by-step plan.
If guided_mode is enabled:
- Use plain English for task descriptions (e.g., "Warm up the shadows", not "Increase offset_r").
- Set "requires_confirmation" to true for EVERY step.
- If a required feature is marked as "guided", create a step explaining what the user should click manually.

Available agents: Color Scientist, Tracking, Skin, Quality, HDR, Match, Enhance, Audio, Render, Film, SkillApply, OS.

ALWAYS respond with ONLY a JSON object matching this schema (no prose, no markdown fences):
{
  "status": "success",
  "plan": [
    {
      "agent": "<AgentName>",
      "task": "<short description>",
      "scope": "<'clip' or 'timeline'>",
      "requires_confirmation": <bool>,
      "params": { <key-value pairs relevant to the agent> }
    }
  ]
}

Rules:
- Scope: Set "scope" to "timeline" if the user wants to apply the look to the whole timeline, or "clip" for the selected clip.
- Confirmation: Set "requires_confirmation" to true for destructive actions or multi-clip scopes.
- Always start with a "Color Scientist" step for basic CDL grading (Slope, Offset, Power, Saturation).
- Understand colorist terms:
  - "Gold skintone": Use Skin agent with a hue shift to orange/yellow + saturation lift in skin qualifier.
  - "Milky shadows": Lifted blacks (offset > 0.02) and reduced contrast.
  - "Bleach bypass": Desaturate (saturation ~0.6) + increase contrast + slight green/cyan offset.
  - "Match BTS feel": If referencing an image, use the SkillApply agent.
- Region Masks: If a region_mask is provided in the context, you MUST specify the operation should be restricted to that region using a Power Window or qualifier. Add "region" to params.
- If the user asks to "apply the [Name] skill" or "use [Name]", use the "SkillApply" agent with params: {"skill_name": "[Name]"}.
- You can specify "append_new_node": true in the Color Scientist params to create a new serial node before applying the CDL, which is great for preserving the existing grade.
- If the user asks to open or close DaVinci Resolve, use the "OS" agent with task "Launch DaVinci" or "Close DaVinci".
- Keep plans to 3-5 steps maximum.
"""

class DirectorAgent:
    def __init__(self, provider: GeminiProvider):
        self.provider = provider

    def analyze_intent(self, user_input: str, guided_mode: bool = False) -> dict:
        """
        Calls Gemini to translate user intent into a concrete execution plan.
        Falls back to a demo plan when no API key is configured.
        """
        logger.info(f"Director analyzing: '{user_input}' (Guided: {guided_mode})")
        
        # Inject capabilities into prompt
        from bridge.capability_probe import CapabilityProbe
        from bridge.connection import get_current_project
        from .rag_engine import rag
        import json
        
        # 1. Query Vector DB for relevant color theory
        theory_context = rag.query_theory(user_input)
        
        resolve, _ = get_current_project()
        caps = {}
        if resolve:
            probe = CapabilityProbe(resolve)
            caps = probe.get_capabilities()
            
        system_prompt = _SYSTEM_PROMPT
        if guided_mode:
            system_prompt += "\n\nCRITICAL: guided_mode is ENABLED for this request. You MUST set requires_confirmation=true for all steps, and use plain English task descriptions."
            
        if caps:
            system_prompt += "\n\nAvailable Features Matrix:\n"
            system_prompt += json.dumps(caps.get("features", {}), indent=2)
            system_prompt += "\nDo not schedule agents for tasks if the required feature is marked as unavailable. If marked as 'guided', create a manual instruction step."

        if theory_context:
            system_prompt += f"\n\nProfessional Color Theory Context (Use this to guide your CDL Math):\n{theory_context}"

        raw = self.provider.generate_response(
            system_prompt=system_prompt,
            user_prompt=user_input,
        )

        # If the provider returned a real content string, parse it
        content = raw.get("content", "") if isinstance(raw, dict) else ""

        if content and "mocked" not in content:
            try:
                # Strip markdown fences if the model wrapped the JSON
                clean = re.sub(r"```(?:json)?", "", content).strip("` \n")
                plan = json.loads(clean)
                logger.info(f"Director parsed plan with {len(plan.get('plan', []))} steps")
                return plan
            except json.JSONDecodeError as e:
                logger.error(f"Director: JSON parse failed ({e}), falling back to demo plan")

        # Fallback demo plan — keeps development unblocked without an API key
        logger.info("Director: using demo plan (no API key or parse error)")
        return {
            "status": "success",
            "plan": [
                {
                    "agent": "Color Scientist",
                    "task": "Apply warm cinematic CDL",
                    "scope": "clip",
                    "requires_confirmation": False,
                    "params": {
                        "slope_r": 1.08, "slope_g": 1.04, "slope_b": 0.96,
                        "offset_r": 0.02, "offset_g": 0.01, "offset_b": -0.01,
                        "power_r": 1.0,  "power_g": 1.0,  "power_b": 1.0,
                        "saturation": 1.05,
                    },
                },
                {
                    "agent": "Skin",
                    "task": "Protect skin tones from over-saturation",
                    "scope": "clip",
                    "requires_confirmation": True,
                    "params": {"mode": "Face"},
                },
                {
                    "agent": "Quality",
                    "task": "Apply subtle noise reduction",
                    "scope": "clip",
                    "requires_confirmation": False,
                    "params": {"strength": 3.0},
                },
            ],
        }

    def plan_timeline(self, user_input: str, clips: list, guided_mode: bool = False) -> dict:
        """
        Timeline-wide planning: passes clip metadata to Gemini so it can generate
        a multi-clip plan (e.g. matching clips, applying a look across everything).
        """
        logger.info(f"Director analyzing timeline scope ({len(clips)} clips): '{user_input}' (Guided: {guided_mode})")
        
        # Build context from clips
        clip_context = "Timeline Clips:\n"
        for clip in clips[:10]: # Limit context for now to avoid token overflow
            clip_context += f"- Track {clip.get('track_index', 1)}, Clip {clip['clip_index']}: {clip['name']} ({clip['duration']} frames)\n"
            
        full_prompt = f"{user_input}\n\nContext:\n{clip_context}"
        
        # For now, reuse analyze_intent which will use the same system prompt
        # The system prompt was updated to know how to emit scope="timeline"
        return self.analyze_intent(full_prompt, guided_mode)

