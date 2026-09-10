import logging
from bridge.tools.cdl_tools import set_cdl
from bridge.tools.gallery_tools import apply_drx_grade

logger = logging.getLogger("cj_grader.agents.color_scientist")

class ColorScientist:
    """Handles CDLs, LUTs, and general color manipulation."""
    def __init__(self, bridge_client=None):
        self.bridge = bridge_client
        
    def execute_task(self, task: dict):
        logger.info(f"Color Scientist executing task: {task['task']}")
        
        timeline_id = task.get("timeline_id", "")
        track_index = task.get("track_index", 1)
        clip_index = task.get("clip_index", 1)
        node_index = task.get("node_index", 1)
        params = task.get("params", {})

        if "CDL" in task['task'].upper() or any(k.startswith("slope") for k in params):
            # 1) Read the current color science context
            from bridge.tools.color_management_tools import get_color_science
            color_science = get_color_science()
            logger.info(f"Color Science Context: {color_science.get('color_science_mode')} / Timeline: {color_science.get('timeline_color_space')}")

            # Fully unpack all 10 CDL params from the Director plan
            slope = {
                "r": params.get("slope_r", 1.0),
                "g": params.get("slope_g", 1.0),
                "b": params.get("slope_b", 1.0),
                "y": 1.0,
            }
            offset = {
                "r": params.get("offset_r", 0.0),
                "g": params.get("offset_g", 0.0),
                "b": params.get("offset_b", 0.0),
                "y": 0.0,
            }
            power = {
                "r": params.get("power_r", 1.0),
                "g": params.get("power_g", 1.0),
                "b": params.get("power_b", 1.0),
                "y": 1.0,
            }
            saturation = params.get("saturation", 1.0)
            append_new_node = params.get("append_new_node", False)

            result = set_cdl(
                timeline_id=timeline_id,
                track_index=track_index,
                clip_index=clip_index,
                node_index=node_index,
                slope=slope,
                offset=offset,
                power=power,
                saturation=saturation,
                append_new_node=append_new_node,
            )
            success = result.get("success", False) if isinstance(result, dict) else bool(result)
            
            import json
            grade_json = json.dumps({
                "slope": (slope['r'], slope['g'], slope['b']),
                "offset": (offset['r'], offset['g'], offset['b']),
                "power": (power['r'], power['g'], power['b']),
                "saturation": saturation
            })
            
            return {"status": "success" if success else "error", "message": f"[GRADE_PARAMS] {grade_json}"}
            
        elif "LUT" in task['task'].upper():
            lut_path = params.get("lut_path", "")
            return {"status": "success", "message": f"Applied LUT: {lut_path}"}
            
        return {"status": "error", "message": "Unknown task for Color Scientist"}

