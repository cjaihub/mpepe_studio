"""gallery_tools — Gallery stills and PowerGrade album management."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.gallery")

def _get_gallery(project):
    return project.GetGallery() if hasattr(project, "GetGallery") else None

def _get_clip(project, track_index: int, clip_index: int):
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return None
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return None
    return items[clip_index - 1]

def grab_still(track_index: int, clip_index: int) -> bool:
    """Grabs a still from the current frame of a clip."""
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if not clip:
        return False
    if hasattr(clip, "GrabStill"):
        return clip.GrabStill()
    return False

def grab_all_stills(still_frame_source: int = 1) -> bool:
    """Grabs stills from all clips on the current timeline."""
    _, project = get_current_project()
    if not project:
        return False
    timeline = project.GetCurrentTimeline()
    if timeline and hasattr(timeline, "GrabAllStills"):
        return timeline.GrabAllStills(still_frame_source)
    return False

def export_still(still, file_path: str, file_format: str = "dpx") -> bool:
    """Exports a gallery still to disk."""
    _, project = get_current_project()
    if not project:
        return False
    gallery = _get_gallery(project)
    if gallery and hasattr(gallery, "ExportStills"):
        return gallery.ExportStills([still], file_path, file_path, file_format)
    return False

def delete_still(still) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    gallery = _get_gallery(project)
    if gallery and hasattr(gallery, "DeleteStills"):
        return gallery.DeleteStills([still])
    return False
