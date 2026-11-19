"""lut_tools — LUT application, retrieval, and refresh."""
import logging
import os
import sys
from typing import List, Dict
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
        return bool(clip.SetLUT(node_index, lut_path))
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


def lut_root() -> str:
    """Resolve's master LUT folder for this OS (overridable with CJ_GRADER_LUT_DIR)."""
    override = os.environ.get("CJ_GRADER_LUT_DIR")
    if override:
        return override
    if sys.platform == "darwin":
        return "/Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT"
    if sys.platform.startswith("win"):
        return os.path.expandvars(r"%PROGRAMDATA%\Blackmagic Design\DaVinci Resolve\Support\LUT")
    return "/opt/resolve/LUT"


def search_luts(keyword: str, limit: int = 10) -> List[Dict[str, str]]:
    """Finds .cube/.3dl LUTs whose file name contains every word of ``keyword``.

    Paths are returned relative to the LUT root with forward slashes, which is the
    form SetLUT accepts.
    """
    root = lut_root()
    if not os.path.isdir(root):
        return []
    words = [w for w in keyword.lower().replace("_", " ").split() if w]
    found = []
    for dirpath, _, files in os.walk(root):
        for name in sorted(files):
            lower = name.lower()
            if not lower.endswith((".cube", ".3dl")):
                continue
            haystack = os.path.relpath(os.path.join(dirpath, name), root).lower().replace("_", " ")
            if all(w in haystack for w in words):
                rel = os.path.relpath(os.path.join(dirpath, name), root).replace("\\", "/")
                found.append({"name": os.path.splitext(name)[0], "path": rel})
                if len(found) >= limit:
                    return found
    return found


def node_count(track_index: int, clip_index: int) -> int:
    """Number of nodes in the clip's grade (0 when unknown)."""
    _, project = get_current_project()
    if not project:
        return 0
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "GetNumNodes"):
        try:
            return int(clip.GetNumNodes() or 0)
        except Exception:
            return 0
    return 0
