"""version_tools — Grade version management (add, load, delete, rename, list)."""
import logging
import datetime
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.version")

GRADE_VERSION_TYPE_LOCAL = 0
GRADE_VERSION_TYPE_REMOTE = 1

def _get_clip(project, track_index: int, clip_index: int):
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return None
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return None
    return items[clip_index - 1]

def take_snapshot(track_index: int, clip_index: int, label: str = "") -> str:
    """
    Creates a named grade version before a grading operation.
    Returns the version name on success, or empty string on failure.
    This is the NON-DESTRUCTIVE safety gate called before every SetCDL.
    """
    _, project = get_current_project()
    if not project:
        logger.warning("take_snapshot: no active project")
        return ""
    clip = _get_clip(project, track_index, clip_index)
    if not clip:
        logger.warning(f"take_snapshot: clip not found track={track_index} clip={clip_index}")
        return ""
    if not hasattr(clip, "AddVersion"):
        logger.warning("take_snapshot: AddVersion not available on this Resolve build")
        return ""

    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    version_name = f"CJ_snap_{ts}" if not label else f"CJ_{label}_{ts}"
    success = clip.AddVersion(version_name, GRADE_VERSION_TYPE_LOCAL)
    if success:
        logger.info(f"Snapshot created: {version_name}")
        return version_name
    else:
        logger.error(f"AddVersion failed for clip {clip_index}")
        return ""

def add_version(track_index: int, clip_index: int, version_name: str, version_type: int = 0) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "AddVersion"):
        return clip.AddVersion(version_name, version_type)
    return False

def load_version(track_index: int, clip_index: int, version_name: str, version_type: int = 0) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "LoadVersionByName"):
        return clip.LoadVersionByName(version_name, version_type)
    return False

def delete_version(track_index: int, clip_index: int, version_name: str, version_type: int = 0) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "DeleteVersionByName"):
        return clip.DeleteVersionByName(version_name, version_type)
    return False

def list_versions(track_index: int, clip_index: int, version_type: int = 0) -> list:
    _, project = get_current_project()
    if not project:
        return []
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "GetVersionNameList"):
        return clip.GetVersionNameList(version_type) or []
    return []

