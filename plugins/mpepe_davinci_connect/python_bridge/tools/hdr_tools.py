"""hdr_tools — Dolby Vision analysis and HDR metadata."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.hdr")

def _get_clip(project, track_index: int, clip_index: int):
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return None
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return None
    return items[clip_index - 1]

def analyze_dolby_vision(track_index: int, clip_index: int) -> bool:
    """Runs Dolby Vision analysis on a clip (requires Studio + Dolby Vision license)."""
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "AnalyzeDolbyVision"):
        return clip.AnalyzeDolbyVision()
    logger.warning("AnalyzeDolbyVision not available on this build.")
    return False
