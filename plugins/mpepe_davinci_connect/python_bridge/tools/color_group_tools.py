"""color_group_tools — Color group creation and clip assignment."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.color_group")

def create_color_group(group_name: str):
    _, project = get_current_project()
    if not project:
        return None
    timeline = project.GetCurrentTimeline()
    if timeline and hasattr(timeline, "AddColorGroup"):
        return timeline.AddColorGroup(group_name)
    return None

def assign_to_group(track_index: int, clip_index: int, color_group) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return False
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return False
    clip = items[clip_index - 1]
    if hasattr(clip, "AssignToColorGroup"):
        return clip.AssignToColorGroup(color_group)
    return False

def remove_from_group(track_index: int, clip_index: int) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return False
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return False
    clip = items[clip_index - 1]
    if hasattr(clip, "RemoveFromColorGroup"):
        return clip.RemoveFromColorGroup()
    return False
