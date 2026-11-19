"""enhance_agent — speed, dynamic zoom, transform and crop on the Edit inspector."""
import logging

from bridge.tools.enhance_tools import set_speed, set_dynamic_zoom, set_transform, set_crop
from .agent_base import AgentBase, step_target, fail, from_bool

logger = logging.getLogger("cj_grader.agents.enhance")

_TRANSFORM_KEYS = {"pan": "Pan", "tilt": "Tilt", "zoom_x": "ZoomX", "zoom_y": "ZoomY",
                   "zoom": "ZoomX", "rotation": "Rotation", "pitch": "Pitch", "yaw": "Yaw"}


class EnhanceAgent(AgentBase):
    name = "Enhance"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "").lower()
        params = task.get("params", {}) or {}
        t = step_target(task)
        track, clip = t["track_index"], t["clip_index"]
        logger.info(f"Enhance Agent: {task_name}")

        if "speed" in task_name or "slow" in task_name or "retime" in task_name:
            speed = float(params.get("speed", 1.0))
            return from_bool(set_speed(track, clip, speed, params.get("retime_process", "OpticalFlow")),
                             f"Speed set to {speed:g}x.", "Resolve rejected the speed change.")

        if "dynamic zoom" in task_name or ("zoom" in task_name and "dynamic" in str(params)):
            enabled = bool(params.get("enabled", True))
            return from_bool(set_dynamic_zoom(track, clip, enabled, params.get("mode")),
                             f"Dynamic Zoom {'on' if enabled else 'off'}.", "Resolve rejected Dynamic Zoom.")

        if "crop" in task_name:
            vals = {k: float(params.get(k, 0)) for k in ("left", "right", "top", "bottom")}
            return from_bool(set_crop(track, clip, **vals), "Crop applied.", "Resolve rejected the crop.")

        if "transform" in task_name or "zoom" in task_name or "rotate" in task_name or "pan" in task_name:
            props = {}
            for key, prop in _TRANSFORM_KEYS.items():
                if key in params:
                    props[prop] = params[key]
            if "zoom" in params:
                props["ZoomY"] = params["zoom"]
            if not props:
                return fail("Transform needs at least one of pan, tilt, zoom, rotation, pitch, yaw.")
            return from_bool(set_transform(track, clip, **props),
                             f"Transform set: {props}.", "Resolve rejected the transform.")

        return fail(f"Unknown task for Enhance: {task.get('task', '')}")
