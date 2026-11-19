"""color_group_tools — Color group creation and clip assignment."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.color_group")

def create_color_group(group_name: str):
    _, project = get_current_project()
    if not project:
        return None
    if hasattr(project, "AddColorGroup"):
        return project.AddColorGroup(group_name)
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


def copy_grade(track_index: int, source_clip_index: int, target_clip_indices: list) -> int:
    """Copies the source clip's grade onto the target clips. Returns how many were copied."""
    _, project = get_current_project()
    if not project:
        return 0
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return 0
    items = timeline.GetItemListInTrack("video", track_index) or []
    if source_clip_index < 1 or source_clip_index > len(items):
        return 0
    source = items[source_clip_index - 1]
    targets = [items[i - 1] for i in target_clip_indices
               if 1 <= i <= len(items) and i != source_clip_index]
    if not targets or not hasattr(source, "CopyGrades"):
        return 0
    return len(targets) if source.CopyGrades(targets) else 0


def find_color_group(group_name: str):
    """Returns an existing color group with this name, or None."""
    _, project = get_current_project()
    if not project or not hasattr(project, "GetColorGroupsList"):
        return None
    for group in project.GetColorGroupsList() or []:
        if hasattr(group, "GetName") and group.GetName() == group_name:
            return group
    return None
