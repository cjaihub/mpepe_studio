"""quality_agent — noise reduction and sharpening.

Resolve's scripting API has no handle on Spatial/Temporal NR or the Blur/Sharpen
palette, so instead of pretending, this agent adds a labelled node for the work
and returns a guided step with the exact settings to dial in.
"""
import logging

from bridge.tools.lut_tools import node_count
from bridge.tools.node_tools import set_node_label
from .agent_base import AgentBase, step_target, fail, guided

logger = logging.getLogger("cj_grader.agents.quality")


def _label_last_node(t: dict, label: str) -> bool:
    count = node_count(t["track_index"], t["clip_index"])
    return bool(count) and set_node_label(t["track_index"], t["clip_index"], count, label)


class QualityAgent(AgentBase):
    name = "Quality"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict):
        task_name = task.get("task", "").lower()
        params = task.get("params", {}) or {}
        t = step_target(task)
        logger.info(f"Quality Agent: {task_name}")

        if "noise" in task_name or "denoise" in task_name or "nr" == task_name.strip():
            strength = float(params.get("strength", 5.0))
            labelled = _label_last_node(t, "NR")
            where = "the node labelled NR" if labelled else "a new serial node (Alt+S)"
            return guided(f"On {where}, open Motion Effects and set Temporal NR frames to 2, "
                          f"Luma/Chroma threshold to {strength:g}, and Spatial NR to {strength:g}.")

        if "sharpen" in task_name:
            amount = float(params.get("amount", 0.5))
            labelled = _label_last_node(t, "Sharpen")
            where = "the node labelled Sharpen" if labelled else "a new serial node (Alt+S)"
            radius = max(0.3, 0.5 - amount * 0.1)
            return guided(f"On {where}, open Blur > Sharpen and lower Radius to {radius:.2f} (RGB linked).")

        return fail(f"Unknown task for Quality: {task.get('task', '')}")
