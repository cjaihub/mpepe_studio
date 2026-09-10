import logging
import os
import glob
from .agent_base import AgentBase
from bridge.tools import gallery_tools

logger = logging.getLogger(__name__)

class LutAgent(AgentBase):
    def __init__(self):
        super().__init__(
            name="LutAgent",
            description="Searches for LUTs and applies them."
        )
        self.lut_dir = r"C:\ProgramData\Blackmagic Design\DaVinci Resolve\Support\LUT"

    def execute(self, prompt: str, timeline_id: str = None, **kwargs) -> dict:
        """
        Executes a LUT search.
        Expected kwargs:
        - keyword: the LUT keyword to search for
        """
        self.emit_progress(1, 3, "Searching for LUTs...")
        
        keyword = kwargs.get('keyword', prompt).lower()
        
        if not os.path.exists(self.lut_dir):
            error_msg = f"LUT directory not found at {self.lut_dir}"
            self.emit_progress(1, 3, error_msg, status="ERROR")
            return {"status": "error", "message": error_msg}
            
        matched_luts = []
        try:
            # Recursively search for .cube files
            for root, dirs, files in os.walk(self.lut_dir):
                for file in files:
                    if file.lower().endswith(".cube") and keyword in file.lower():
                        # We want the relative path from the LUT root, as that's what Resolve usually expects
                        rel_path = os.path.relpath(os.path.join(root, file), self.lut_dir)
                        # Replace backslashes with forward slashes for cross-platform resolve compatibility
                        rel_path = rel_path.replace("\\", "/")
                        matched_luts.append({
                            "name": file.replace(".cube", ""),
                            "path": rel_path
                        })
                        if len(matched_luts) >= 10: # Limit results
                            break
                if len(matched_luts) >= 10:
                    break
        except Exception as e:
            logger.error(f"Error searching LUTs: {e}")
            
        if not matched_luts:
            self.emit_progress(2, 3, f"No LUTs found matching '{keyword}'", status="DONE")
            return {"status": "success", "message": f"No LUTs found for '{keyword}'"}
            
        self.emit_progress(2, 3, f"Found {len(matched_luts)} LUTs matching '{keyword}'")
        
        # Format the math for the Flutter visualizer
        import json
        lut_json = json.dumps({"luts": matched_luts})
        detail_msg = f"[LUT_RESULTS] {lut_json}"
        
        self.emit_progress(3, 3, "LUT search complete.", status="DONE", detail=detail_msg)
        return {"status": "success", "message": f"Found {len(matched_luts)} LUTs."}
