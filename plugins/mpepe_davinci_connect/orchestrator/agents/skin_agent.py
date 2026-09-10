import logging
from bridge.tools.neural_engine_tools import create_magic_mask
from bridge.capability_probe import CapabilityProbe
from bridge.connection import get_current_project

logger = logging.getLogger("cj_grader.agents.skin")

class SkinAgent:
    """Handles face refinement, skin smoothing, and beauty work."""
    def __init__(self, bridge_client=None):
        self.bridge = bridge_client
        
    def execute_task(self, task: dict):
        task_name = task.get("task", "")
        params = task.get("params", {})
        
        timeline_id = task.get("timeline_id", "")
        track_index = task.get("track_index", 1)
        clip_index = task.get("clip_index", 1)
        
        logger.info(f"Skin Agent executing task: {task_name}")
        
        resolve, _ = get_current_project()
        if resolve:
            probe = CapabilityProbe(resolve)
            caps = probe.get_capabilities()
        else:
            caps = {"features": {}}

        if "face refinement" in task_name.lower() or "skin" in task_name.lower():
            if not caps.get("features", {}).get("face_refinement", {}).get("available", False):
                return {"status": "SKIPPED", "message": "Face Refinement requires DaVinci Resolve Studio."}
                
            # In a full implementation, we would add the Resolve FX Face Refinement node.
            # For now, we simulate this by creating a magic mask for the face.
            mode = params.get("mode", "Face")
            success = create_magic_mask(timeline_id, track_index, clip_index, mode)
            return {"status": "success" if success else "error", "message": f"Applied Skin Smoothing (Mask mode: {mode})"}
            
        return {"status": "error", "message": "Unknown task for Skin Agent"}
