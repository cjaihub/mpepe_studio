"""hdr_agent — Dolby Vision analysis and HDR metadata."""
import logging

from bridge.tools.hdr_tools import analyze_dolby_vision
from .agent_base import AgentBase, step_target, fail, from_bool

logger = logging.getLogger("cj_grader.agents.hdr")


class HdrAgent(AgentBase):
    name = "HDR"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict):
        task_name = task.get("task", "").lower()
        t = step_target(task)
        logger.info(f"HDR Agent: {task_name}")

        if "dolby" in task_name or "analy" in task_name or "hdr" in task_name:
            success = analyze_dolby_vision(t["track_index"], t["clip_index"])
            return from_bool(success, "Dolby Vision analysis complete.",
                             "Dolby Vision analysis failed (needs Studio with Dolby Vision enabled).")
        return fail(f"Unknown task for HDR: {task.get('task', '')}")
