"""render_tools — Render queue, job management, and Quick Export."""
import logging
from typing import Optional, Dict, Any, List
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.render")

def add_render_job(render_settings: Dict[str, Any]) -> Optional[str]:
    """Adds a render job to the queue and returns job ID."""
    _, project = get_current_project()
    if not project:
        return None
    if hasattr(project, "SetRenderSettings"):
        project.SetRenderSettings(render_settings)
    if hasattr(project, "AddRenderJob"):
        return project.AddRenderJob()
    return None

def start_render() -> bool:
    """Starts rendering all queued jobs."""
    _, project = get_current_project()
    if not project:
        return False
    if hasattr(project, "StartRendering"):
        return project.StartRendering()
    return False

def get_render_status() -> List[Dict[str, Any]]:
    """Returns the current render job list and status."""
    _, project = get_current_project()
    if not project:
        return []
    if hasattr(project, "GetRenderJobList"):
        return project.GetRenderJobList() or []
    return []
