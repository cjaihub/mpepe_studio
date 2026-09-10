"""match_agent — Shot/camera matching, grade copy, and color groups."""
import logging

logger = logging.getLogger("cj_grader.agents.match")

class MatchAgent:
    def __init__(self, bridge_client):
        self.bridge = bridge_client

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "")
        params = task.get("params", {})
        logger.info(f"Match Agent: {task_name}")

        if "copy" in task_name.lower() or "match" in task_name.lower():
            target_clips = params.get("target_clips", [])
            # self.bridge.CopyGrades(target_clips=target_clips)
            return {"status": "success", "action": f"GradeCopied to {len(target_clips)} clips"}

        elif "group" in task_name.lower():
            group_name = params.get("group_name", "Group 1")
            return {"status": "success", "action": f"ColorGroup({group_name})"}

        return {"status": "error", "message": f"Unknown task for Match: {task_name}"}
