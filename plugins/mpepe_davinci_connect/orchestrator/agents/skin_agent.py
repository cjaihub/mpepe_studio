"""skin_agent — skin tone work: Magic Mask isolation plus a gentle skin CDL."""
import logging

from bridge.capability_probe import current_capabilities
from bridge.tools.neural_engine_tools import create_magic_mask
from .agent_base import AgentBase, step_target, ok, fail, skipped, guided

logger = logging.getLogger("cj_grader.agents.skin")


class SkinAgent(AgentBase):
    """Isolates faces with Magic Mask. Face Refinement itself has no scripting API, so the
    agent creates the mask and tells the user the one click that remains."""
    name = "Skin"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict):
        task_name = task.get("task", "")
        params = task.get("params", {}) or {}
        target = step_target(task)
        logger.info(f"Skin Agent: {task_name}")

        caps = current_capabilities()
        if not caps.get("features", {}).get("magic_mask", {}).get("available", False):
            return skipped("Skin isolation uses Magic Mask, which needs DaVinci Resolve Studio.")

        direction = params.get("direction", "F")
        if not create_magic_mask(target["timeline_id"], target["track_index"], target["clip_index"], direction):
            return fail("Magic Mask could not be created on this clip.")

        # Optional subtle skin CDL on top of the mask (e.g. "gold skintone")
        if any(k.startswith(("slope", "offset", "power", "saturation")) for k in params):
            from .color_scientist import apply_cdl_to_target
            result = apply_cdl_to_target(target, params, "skin_agent")
            if result["status"] != "success":
                return result

        if "refine" in task_name.lower() or "smooth" in task_name.lower():
            return guided("Face mask is tracked. To finish, open Effects > Face Refinement on this "
                          "node and adjust Smoothing.")
        return ok("Face isolated with Magic Mask.")
