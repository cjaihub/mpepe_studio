"""tracking_agent — Magic Mask, stabilization, and smart reframe tasks."""
import logging
from bridge.tools.neural_engine_tools import create_magic_mask, stabilize, smart_reframe
from bridge.capability_probe import CapabilityProbe
from bridge.connection import get_current_project

logger = logging.getLogger("cj_grader.agents.tracking")

class TrackingAgent:
    def __init__(self, bridge_client=None):
        self.bridge = bridge_client

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "")
        params = task.get("params", {})
        
        timeline_id = task.get("timeline_id", "")
        track_index = task.get("track_index", 1)
        clip_index = task.get("clip_index", 1)
        
        logger.info(f"Tracking Agent: {task_name}")
        
        resolve, _ = get_current_project()
        if resolve:
            probe = CapabilityProbe(resolve)
            caps = probe.get_capabilities()
        else:
            caps = {"features": {}}

        if "Magic Mask" in task_name or "mask" in task_name.lower():
            if not caps.get("features", {}).get("magic_mask", {}).get("available", False):
                return {"status": "SKIPPED", "message": "Magic Mask requires DaVinci Resolve Studio."}
            mode = params.get("mode", "F")
            success = create_magic_mask(timeline_id, track_index, clip_index, mode)
            return {"status": "success" if success else "error", "action": f"MagicMask({mode})"}

        elif "stabiliz" in task_name.lower():
            success = stabilize(timeline_id, track_index, clip_index)
            return {"status": "success" if success else "error", "action": "Stabilize"}

        elif "reframe" in task_name.lower():
            if not caps.get("features", {}).get("smart_reframe", {}).get("available", False):
                return {"status": "SKIPPED", "message": "Smart Reframe requires DaVinci Resolve Studio."}
            success = smart_reframe(timeline_id, track_index, clip_index)
            return {"status": "success" if success else "error", "action": "SmartReframe"}

        return {"status": "error", "message": f"Unknown task for Tracking: {task_name}"}
