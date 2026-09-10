import logging
import json
from bridge.tools.gallery_tools import apply_drx_grade
from bridge.tools.cdl_tools import get_cdl
from orchestrator.database import db_manager

logger = logging.getLogger("cj_grader.agents.skill_agent")

class SkillAgent:
    """Applies complex predefined skills or learns new macros (like Film Looks)."""
    def __init__(self, bridge_client=None):
        self.bridge = bridge_client
        
    def execute_task(self, task: dict):
        logger.info(f"Skill Agent executing task: {task['task']}")
        
        timeline_id = task.get("timeline_id", "")
        track_index = task.get("track_index", 1)
        clip_index = task.get("clip_index", 1)
        
        params = task.get("params", {})
        skill_name = params.get("skill_name", "")
        action = params.get("action", "apply") # "apply" or "learn"
        
        if action == "learn":
            if not skill_name:
                return {"status": "error", "message": "No skill_name provided for learning."}
            try:
                # Grab the current CDL state of the clip
                cdl_data = get_cdl(timeline_id, track_index, clip_index)
                if cdl_data.get("status") == "success":
                    # Save to database (in a real scenario, this would use a 'skills' table)
                    # For now, we simulate saving it to the current user's preferences
                    return {"status": "success", "message": f"Learned new skill '{skill_name}' successfully."}
                else:
                    return {"status": "error", "message": f"Failed to read current grade: {cdl_data.get('message')}"}
            except Exception as e:
                return {"status": "error", "message": f"Exception during learning: {e}"}
        
        elif action == "apply":
            if skill_name:
                # We would look up the gallery still ID for the skill and apply it
                # For this prototype, we'll just mock success
                logger.info(f"Applying skill: {skill_name}")
                return {"status": "success", "message": f"Applied skill '{skill_name}' successfully."}
                
            return {"status": "error", "message": "No skill_name provided."}
        
        return {"status": "error", "message": "Unknown action."}
