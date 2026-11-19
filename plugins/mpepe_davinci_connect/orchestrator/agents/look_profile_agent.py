"""look_profile_agent — turns a reference image or a text description into a reusable LookProfile."""
import json
import logging
import os
import uuid
from typing import Any, Dict

from orchestrator.look_profile import LookProfile
from orchestrator.provider_abstraction import get_provider
from .agent_base import AgentBase, CDL_JSON_PROMPT, cdl_from_vision_reply, parse_json_reply, ok, fail

logger = logging.getLogger("cj_grader.agents.look_profile")

_TEXT_PROMPT = (
    "You are an expert colorist. Turn the user's description of a look into an ASC CDL for "
    "DaVinci Resolve. Keep values subtle (slope 0.8-1.2, offset -0.05-0.05, power 0.8-1.2, "
    "saturation 0.6-1.4). Respond ONLY with JSON: {\"description\": \"...\", \"tags\": [\"...\"], "
    "\"cdl\": {\"slope_r\": 1.0, \"slope_g\": 1.0, \"slope_b\": 1.0, \"offset_r\": 0.0, \"offset_g\": 0.0, "
    "\"offset_b\": 0.0, \"power_r\": 1.0, \"power_g\": 1.0, \"power_b\": 1.0, \"saturation\": 1.0}}"
)


class LookProfileAgent(AgentBase):
    name = "LookProfile"

    def __init__(self, bridge_client: Any = None, provider=None):
        super().__init__(bridge_client=bridge_client)
        self._provider = provider

    @property
    def provider(self):
        return self._provider or get_provider()

    def get_name(self) -> str:
        return "LookProfile Agent"

    def execute_task(self, step_info: Dict[str, Any]) -> Dict[str, Any]:
        params = step_info.get("params", {}) or {}
        image_path = params.get("image_path")
        if image_path:
            return self._analyze_image_file(image_path, step_info.get("task", ""))
        return self._generate_from_text(params.get("description") or step_info.get("task", ""), params)

    def _profile_result(self, look: Dict[str, Any], name: str, image_uri: str = None) -> Dict[str, Any]:
        profile = LookProfile(id=str(uuid.uuid4()), name=name,
                              description=look.get("description") or name,
                              cdl_params=look["cdl"], tags=look.get("tags", []),
                              reference_image_uri=image_uri)
        return ok(f"Look ready: {profile.description}", profile=profile.to_json(),
                  detail=f"[LOOK_PROFILE] {profile.to_json()}")

    def _analyze_image_file(self, image_path: str, task_desc: str) -> Dict[str, Any]:
        logger.info(f"Analyzing reference image at {image_path}")
        try:
            with open(image_path, "rb") as f:
                image_bytes = f.read()
            look = cdl_from_vision_reply(self.provider.analyze_image(CDL_JSON_PROMPT, image_bytes))
        except Exception as e:
            logger.error(f"LookProfile image analysis failed: {e}")
            return fail(str(e))
        return self._profile_result(look, f"Look from {os.path.basename(image_path)}", image_path)

    def _generate_from_text(self, task_desc: str, params: Dict[str, Any]) -> Dict[str, Any]:
        if not task_desc.strip():
            return fail("Describe the look you want.")
        logger.info(f"Generating look from text: {task_desc}")
        reply = self.provider.generate_response(system_prompt=_TEXT_PROMPT, user_prompt=task_desc)
        try:
            if reply.get("error"):
                raise ValueError(reply["error"])
            data = parse_json_reply(reply.get("content", ""))
            look = {"description": data.get("description", task_desc), "tags": data.get("tags", []),
                    "cdl": {k: float(v) for k, v in (data.get("cdl") or {}).items()}}
            if not look["cdl"]:
                raise ValueError("model returned no CDL")
        except Exception as e:
            return fail(f"Could not build a look from that description ({e}). "
                        "Is GEMINI_API_KEY or CJ_GRADER_PROXY_URL set?")
        return self._profile_result(look, params.get("name") or task_desc[:40])
