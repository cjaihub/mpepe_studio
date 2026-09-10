import logging
from bridge.tools.hdr_tools import analyze_dolby_vision

logger = logging.getLogger("cj_grader.agents.hdr")

class HdrAgent:
    """Handles Dolby Vision analysis and HDR metadata."""
    def __init__(self, bridge_client=None):
        self.bridge = bridge_client
        
    def execute_task(self, task: dict):
        task_name = task.get("task", "")
        params = task.get("params", {})
        
        timeline_id = task.get("timeline_id", "")
        track_index = task.get("track_index", 1)
        clip_index = task.get("clip_index", 1)
        
        logger.info(f"HDR Agent executing task: {task_name}")

        if "dolby vision" in task_name.lower() or "analyze" in task_name.lower():
            success = analyze_dolby_vision(track_index, clip_index)
            return {"status": "success" if success else "error", "message": "Triggered Dolby Vision Analysis"}
            
        return {"status": "error", "message": "Unknown task for HDR Agent"}
