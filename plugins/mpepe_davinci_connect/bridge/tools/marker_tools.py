"""marker_tools — Clip marker and flag annotation."""
import logging
from typing import Dict, Any
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.marker")

def _get_clip(project, track_index: int, clip_index: int):
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return None
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return None
    return items[clip_index - 1]

def add_marker(track_index: int, clip_index: int, frame_id: int,
               color: str = "Blue", name: str = "", note: str = "") -> bool:
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "AddMarker"):
        return clip.AddMarker(frame_id, color, name, note, 1)
    return False

def get_markers(track_index: int, clip_index: int) -> Dict[int, Any]:
    _, project = get_current_project()
    if not project:
        return {}
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "GetMarkers"):
        return clip.GetMarkers() or {}
    return {}

def delete_marker(track_index: int, clip_index: int, frame_id: int) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "DeleteMarkerAtFrame"):
        return clip.DeleteMarkerAtFrame(frame_id)
    return False
