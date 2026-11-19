"""agent_base — shared contract for CJ Grader agents.

Every agent the Executor runs exposes ``execute_task(step) -> dict``. The result
dict always carries a ``status``:

  success  — the action ran in Resolve
  error    — the action was attempted and failed (or could not be attempted)
  skipped  — the action is not available on this install (e.g. needs Studio)
  guided   — Resolve's scripting API cannot do this; ``message`` tells the user
             what to click

Optionally ``detail`` holds a tagged payload for the Flutter UI, e.g.
``[GRADE_PARAMS] {...}``. ``message`` is a short human-readable summary.

Agents may report intermediate progress with ``emit_progress``; the Executor
installs a per-thread sink so concurrent plans never mix their events.
"""
import logging
import threading
from typing import Any, Callable, Dict, Optional

logger = logging.getLogger("cj_grader.agents.base")

_progress = threading.local()


def set_progress_sink(sink: Optional[Callable[[str, str], None]]):
    """Executor hook: route emit_progress() calls on this thread to ``sink(message, detail)``."""
    _progress.sink = sink


def step_target(step: Dict[str, Any]) -> Dict[str, Any]:
    """Pulls the clip address the Executor stamped onto a plan step."""
    params = step.get("params", {}) or {}
    return {
        "timeline_id": step.get("timeline_id", "") or "",
        "track_index": int(step.get("track_index") or params.get("track_index") or 1),
        "clip_index": int(step.get("clip_index") or params.get("clip_index") or 1),
        "node_index": int(step.get("node_index") or params.get("node_index") or 1),
    }


def ok(message: str, detail: str = "", **extra) -> Dict[str, Any]:
    return {"status": "success", "message": message, "detail": detail, **extra}


def fail(message: str, **extra) -> Dict[str, Any]:
    return {"status": "error", "message": message, **extra}


def skipped(message: str, **extra) -> Dict[str, Any]:
    return {"status": "skipped", "message": message, **extra}


def guided(message: str, **extra) -> Dict[str, Any]:
    return {"status": "guided", "message": message, **extra}


def from_bool(success: bool, ok_msg: str, fail_msg: str, **extra) -> Dict[str, Any]:
    return ok(ok_msg, **extra) if success else fail(fail_msg, **extra)


class AgentBase:
    """Base for agents written in the ``execute(prompt, timeline_id, **params)`` style."""

    name = "Agent"
    description = ""

    def __init__(self, name: str = "", description: str = "", bridge_client: Any = None):
        if name:
            self.name = name
        if description:
            self.description = description
        self.bridge = bridge_client

    def emit_progress(self, step: int, total: int, message: str,
                      status: str = "RUNNING", detail: str = ""):
        logger.info(f"[{self.name}] ({step}/{total}) {message}")
        sink = getattr(_progress, "sink", None)
        if sink and status == "RUNNING":
            try:
                sink(message, detail)
            except Exception as e:  # progress must never break the agent
                logger.debug(f"progress sink failed: {e}")

    def execute_task(self, step: Dict[str, Any]) -> Dict[str, Any]:
        params = dict(step.get("params", {}) or {})
        target = step_target(step)
        for key, value in target.items():
            params.setdefault(key, value)
        timeline_id = params.pop("timeline_id", "") or target["timeline_id"]
        return self.execute(step.get("task", ""), timeline_id=timeline_id, **params)

    def execute(self, prompt: str, timeline_id: str = None, **kwargs) -> Dict[str, Any]:
        raise NotImplementedError


def parse_json_reply(content: str) -> Dict[str, Any]:
    """Parses a model reply that should be JSON, tolerating ``` fences and leading prose."""
    import json
    import re
    text = re.sub(r"```(?:json)?", "", content or "").strip("` \n")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end > start:
            return json.loads(text[start:end + 1])
        raise


CDL_JSON_PROMPT = (
    "You are an expert colorist. Analyze this reference frame's contrast, exposure, white balance "
    "and split toning, and express the look as an ASC CDL for DaVinci Resolve. Keep values subtle "
    "(slope 0.8-1.2, offset -0.05-0.05, power 0.8-1.2, saturation 0.6-1.4).\n"
    "Respond ONLY with JSON: {\"description\": \"...\", \"tags\": [\"...\"], \"cdl\": {\"slope_r\": 1.0, "
    "\"slope_g\": 1.0, \"slope_b\": 1.0, \"offset_r\": 0.0, \"offset_g\": 0.0, \"offset_b\": 0.0, "
    "\"power_r\": 1.0, \"power_g\": 1.0, \"power_b\": 1.0, \"saturation\": 1.0}}"
)


def cdl_from_vision_reply(reply: Dict[str, Any]) -> Dict[str, Any]:
    """Extracts {description, tags, cdl} from a provider.analyze_image() reply. Raises on bad output."""
    if reply.get("error"):
        raise ValueError(reply["error"])
    data = parse_json_reply(reply.get("content", ""))
    cdl = data.get("cdl") or (data.get("look") or {}).get("cdl")
    if not isinstance(cdl, dict) or not cdl:
        raise ValueError("Vision model returned no CDL")
    return {"description": data.get("description") or (data.get("look") or {}).get("description", ""),
            "tags": data.get("tags", []), "cdl": {k: float(v) for k, v in cdl.items()}}
