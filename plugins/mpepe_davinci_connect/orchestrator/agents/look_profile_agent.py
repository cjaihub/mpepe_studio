import logging
from typing import Dict, Any, Optional
from orchestrator.agent_protocol import Agent
from orchestrator.provider_abstraction import GeminiProvider
from orchestrator.look_profile import LookProfile
import uuid

logger = logging.getLogger("cj_grader.agents.look_profile")

class LookProfileAgent(Agent):
    """
    Agent responsible for analyzing reference images or text descriptions
    to generate reusable LookProfile instances (CDL + metadata).
    """

    def __init__(self, bridge_client: Any = None):
        # The agent can use the bridge client if it needs to query Resolve,
        # but primarily it interacts with Gemini Vision.
        self.bridge_client = bridge_client
        self.provider = GeminiProvider() # Grabs key/proxy from env

    def get_name(self) -> str:
        return "LookProfile Agent"

    def execute_task(self, step_info: Dict[str, Any]) -> Dict[str, Any]:
        params = step_info.get("params", {})
        task_desc = step_info.get("task", "")
        
        # Is this an image analysis task or just text?
        image_path = params.get("image_path")
        
        if image_path:
            return self._analyze_image_file(image_path, task_desc)
        else:
            return self._generate_from_text(task_desc, params)
            
    def _analyze_image_file(self, image_path: str, task_desc: str) -> Dict[str, Any]:
        logger.info(f"Analyzing reference image at {image_path}")
        
        try:
            with open(image_path, "rb") as f:
                image_bytes = f.read()
                
            prompt = (
                "You are an expert colorist. Analyze this reference image and extract its cinematic look. "
                "Determine the appropriate CDL parameters (slope, offset, power, saturation) "
                "to achieve a similar look in DaVinci Resolve. "
                "Also provide a short description of the look and 3-5 tags (e.g. 'warm', 'contrasty').\n\n"
                "Respond ONLY with a JSON object in this format:\n"
                "{\n"
                '  "description": "...",\n'
                '  "tags": ["..."],\n'
                '  "cdl": {"slope_r": 1.0, ...}\n'
                "}"
            )
            
            response = self.provider.analyze_image(prompt, image_bytes)
            
            if "error" in response:
                return {"status": "error", "message": response["error"]}
                
            # Parse the response
            content = response.get("content", "")
            
            # Very basic cleanup (assuming it returns JSON directly as requested)
            import re
            import json
            clean = re.sub(r"```(?:json)?", "", content).strip("` \n")
            
            try:
                look_data = json.loads(clean)
                
                # Generate a profile
                profile = LookProfile(
                    id=str(uuid.uuid4()),
                    name=f"Look from {image_path.split('/')[-1]}",
                    description=look_data.get("description", "Generated from reference image"),
                    cdl_params=look_data.get("cdl", {}),
                    tags=look_data.get("tags", []),
                    reference_image_uri=image_path
                )
                
                return {
                    "status": "success",
                    "profile": profile.to_json(),
                    "message": f"Successfully analyzed image: {profile.description}"
                }
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse vision response: {content}")
                return {"status": "error", "message": f"Invalid JSON from vision model: {e}"}
                
        except Exception as e:
            logger.error(f"Error in LookProfileAgent: {e}")
            return {"status": "error", "message": str(e)}

    def _generate_from_text(self, task_desc: str, params: Dict[str, Any]) -> Dict[str, Any]:
        # For now, just a stub for purely text-based look generation
        # (Could also just use Director + ColorScientist for this)
        logger.info(f"Generating look from text: {task_desc}")
        
        # In a real implementation, we might call Gemini text here
        return {
            "status": "success", 
            "message": "Text-based look generation not fully implemented yet."
        }
