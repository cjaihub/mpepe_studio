"""reference_agent — matches the clip to a reference image using Gemini Vision + CDL."""
import base64
import logging

from ..provider_abstraction import get_provider
from .agent_base import AgentBase, CDL_JSON_PROMPT, cdl_from_vision_reply, fail
from .color_scientist import apply_cdl_to_target

logger = logging.getLogger("cj_grader.agents.reference")


class ReferenceAgent(AgentBase):
    def __init__(self, provider=None):
        super().__init__(
            name="Reference",
            description="Analyzes a reference image and matches the current clip to its look.",
        )
        self._provider = provider

    @property
    def provider(self):
        return self._provider or get_provider()

    def execute(self, prompt: str, timeline_id: str = None, **kwargs) -> dict:
        reference = kwargs.get("frame_bytes")
        if isinstance(reference, str):  # base64 from JSON plans
            reference = base64.b64decode(reference)
        if not reference and kwargs.get("image_path"):
            try:
                with open(kwargs["image_path"], "rb") as f:
                    reference = f.read()
            except OSError as e:
                return fail(f"Cannot read reference image: {e}")
        if not reference:
            return fail("No reference image provided (frame_bytes or image_path).")

        self.emit_progress(1, 3, "Analyzing reference image...")
        hint = f"\nThe user also asked: {kwargs.get('prompt') or prompt}" if (kwargs.get("prompt") or prompt) else ""
        try:
            look = cdl_from_vision_reply(self.provider.analyze_image(CDL_JSON_PROMPT + hint, reference))
        except Exception as e:
            return fail(f"Could not derive a look from the reference: {e}")

        self.emit_progress(2, 3, f"Matching look: {look['description'] or 'reference'}")
        target = {
            "timeline_id": timeline_id or "",
            "track_index": int(kwargs.get("track_index", 1)),
            "clip_index": int(kwargs.get("clip_index", 1)),
            "node_index": int(kwargs.get("node_index", 1)),
        }
        result = apply_cdl_to_target(target, look["cdl"], "reference_agent",
                                     append_new_node=bool(kwargs.get("append_new_node", True)))
        if result["status"] == "success":
            result["message"] = f"Matched reference ({look['description']}). " + result["message"]
        return result
