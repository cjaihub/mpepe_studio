"""render_agent — queues and starts renders, reports render status."""
import json
import logging
import os

from bridge.tools.render_tools import add_render_job, start_render, get_render_status
from .agent_base import AgentBase, ok, fail

logger = logging.getLogger("cj_grader.agents.render")

# Director param name -> Resolve SetRenderSettings key
_SETTING_KEYS = {
    "target_dir": "TargetDir", "custom_name": "CustomName",
    "width": "FormatWidth", "height": "FormatHeight", "frame_rate": "FrameRate",
    "mark_in": "MarkIn", "mark_out": "MarkOut", "select_all_frames": "SelectAllFrames",
}


class RenderAgent(AgentBase):
    name = "Render"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "").lower()
        params = task.get("params", {}) or {}
        logger.info(f"Render Agent: {task_name}")

        if "status" in task_name or "progress" in task_name:
            jobs = get_render_status()
            return ok(f"{len(jobs)} job(s) in the render queue.", detail=f"[RENDER_JOBS] {json.dumps(jobs, default=str)}")

        if "render" in task_name or "export" in task_name or "deliver" in task_name:
            settings = {"SelectAllFrames": True,
                        "TargetDir": os.path.expanduser(params.get("target_dir", "~/Movies/CJ Grader"))}
            for key, value in params.items():
                if key in _SETTING_KEYS and key != "target_dir":
                    settings[_SETTING_KEYS[key]] = value
            os.makedirs(settings["TargetDir"], exist_ok=True)
            job_id = add_render_job(settings)
            if not job_id:
                return fail("Resolve did not accept the render job (check a timeline is open).")
            if params.get("start", True):
                if not start_render():
                    return fail(f"Queued job {job_id} but Resolve would not start rendering.")
                return ok(f"Rendering to {settings['TargetDir']} (job {job_id}).")
            return ok(f"Queued render job {job_id}.")

        return fail(f"Unknown task for Render: {task.get('task', '')}")
