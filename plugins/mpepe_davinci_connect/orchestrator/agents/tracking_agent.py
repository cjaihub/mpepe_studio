"""tracking_agent — Magic Mask, stabilization, and smart reframe tasks."""
import logging

from bridge.capability_probe import current_capabilities
from bridge.tools.neural_engine_tools import create_magic_mask, stabilize, smart_reframe
from .agent_base import AgentBase, step_target, fail, skipped, from_bool

logger = logging.getLogger("cj_grader.agents.tracking")


class TrackingAgent(AgentBase):
    name = "Tracking"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "").lower()
        params = task.get("params", {}) or {}
        t = step_target(task)
        logger.info(f"Tracking Agent: {task_name}")
        features = current_capabilities().get("features", {})

        if "mask" in task_name:
            if not features.get("magic_mask", {}).get("available", False):
                return skipped("Magic Mask requires DaVinci Resolve Studio.")
            ok_ = create_magic_mask(t["timeline_id"], t["track_index"], t["clip_index"], params.get("direction", "F"))
            return from_bool(ok_, "Magic Mask tracked.", "Magic Mask failed on this clip.")

        if "stabiliz" in task_name or "stabilis" in task_name:
            ok_ = stabilize(t["timeline_id"], t["track_index"], t["clip_index"])
            return from_bool(ok_, "Clip stabilized.", "Stabilization failed on this clip.")

        if "reframe" in task_name:
            if not features.get("smart_reframe", {}).get("available", False):
                return skipped("Smart Reframe requires DaVinci Resolve Studio.")
            ok_ = smart_reframe(t["timeline_id"], t["track_index"], t["clip_index"])
            return from_bool(ok_, "Smart Reframe applied.", "Smart Reframe failed on this clip.")

        return fail(f"Unknown task for Tracking: {task.get('task', '')}")
