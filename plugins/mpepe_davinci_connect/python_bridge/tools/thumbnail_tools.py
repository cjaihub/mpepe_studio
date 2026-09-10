"""thumbnail_tools — Frame thumbnail extraction for AI vision analysis."""
import logging
from typing import Optional, Dict, Any
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.thumbnail")

def get_thumbnail(track_index: int, clip_index: int, width: int = 256, height: int = 144) -> Optional[Dict[str, Any]]:
    """Returns a thumbnail dict with format, data keys for the current frame of a clip."""
    _, project = get_current_project()
    if not project:
        return None
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return None
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return None
    clip = items[clip_index - 1]
    if hasattr(clip, "GetCurrentClipThumbnailImage"):
        return clip.GetCurrentClipThumbnailImage()
    logger.warning("GetCurrentClipThumbnailImage not available.")
    return None
