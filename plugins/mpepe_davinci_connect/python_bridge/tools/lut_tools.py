"""lut_tools — LUT application, retrieval, and refresh."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.lut")

def _get_clip(project, track_index: int, clip_index: int):
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return None
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return None
    return items[clip_index - 1]

def set_lut(timeline_id: str, track_index: int, clip_index: int, node_index: int, lut_path: str) -> bool:
    """Applies a LUT to a specific node on a clip."""
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if not clip:
        return False
    # node_index is 1-based. SetLUT takes the NodeIndex and lut path.
    if hasattr(clip, "SetLUT"):
        return clip.SetLUT(node_index, lut_path)
    logger.error("SetLUT not supported.")
    return False

def get_lut(timeline_id: str, track_index: int, clip_index: int, node_index: int) -> str:
    """Returns the LUT path applied to a specific node."""
    _, project = get_current_project()
    if not project:
        return ""
    clip = _get_clip(project, track_index, clip_index)
    if not clip:
        return ""
    if hasattr(clip, "GetLUT"):
        return clip.GetLUT(node_index)
    return ""

def refresh_lut_list(project) -> bool:
    """Refreshes the LUT list from disk."""
    if hasattr(project, "RefreshLUTList"):
        return project.RefreshLUTList()
    return False
