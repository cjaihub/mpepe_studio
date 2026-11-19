"""match_agent — shot matching via grade copy, and color groups."""
import logging

from bridge.tools.color_group_tools import (
    copy_grade, create_color_group, assign_to_group, find_color_group,
)
from bridge.tools.timeline_tools import get_all_clips
from .agent_base import AgentBase, step_target, ok, fail

logger = logging.getLogger("cj_grader.agents.match")


def _targets(params: dict, t: dict) -> list:
    """Explicit ``target_clips`` or, when absent, every other clip on the track."""
    targets = params.get("target_clips")
    if targets:
        return [int(i) for i in targets]
    return [c["clip_index"] for c in get_all_clips(t["timeline_id"], t["track_index"])
            if c["clip_index"] != t["clip_index"]]


class MatchAgent(AgentBase):
    name = "Match"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "").lower()
        params = task.get("params", {}) or {}
        t = step_target(task)
        logger.info(f"Match Agent: {task_name}")

        if "group" in task_name:
            group_name = params.get("group_name", "CJ Group")
            group = find_color_group(group_name) or create_color_group(group_name)
            if not group:
                return fail(f"Could not create color group '{group_name}'.")
            members = [t["clip_index"]] + [i for i in (params.get("target_clips") or []) if i != t["clip_index"]]
            added = sum(1 for i in members if assign_to_group(t["track_index"], int(i), group))
            if not added:
                return fail(f"No clips could be added to '{group_name}'.")
            return ok(f"Added {added} clip(s) to color group '{group_name}'.")

        if "copy" in task_name or "match" in task_name or "apply to all" in task_name:
            targets = _targets(params, t)
            if not targets:
                return fail("No target clips to match.")
            copied = copy_grade(t["track_index"], t["clip_index"], targets)
            if not copied:
                return fail("Resolve could not copy the grade (CopyGrades unavailable or clips missing).")
            return ok(f"Copied clip {t['clip_index']}'s grade to {copied} clip(s).")

        return fail(f"Unknown task for Match: {task.get('task', '')}")
