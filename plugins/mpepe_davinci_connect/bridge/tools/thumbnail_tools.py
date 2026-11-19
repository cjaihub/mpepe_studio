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
    # Resolve exposes the thumbnail on the Timeline (Color page, current clip).
    if hasattr(timeline, "GetCurrentClipThumbnailImage"):
        return timeline.GetCurrentClipThumbnailImage()
    logger.warning("GetCurrentClipThumbnailImage not available.")
    return None


def frames_to_timecode(frame: int, fps: float) -> str:
    """Non-drop-frame HH:MM:SS:FF for a timeline frame number."""
    rate = max(1, int(round(float(fps or 24))))
    frame = max(0, int(frame))
    ff = frame % rate
    total_seconds = frame // rate
    return f"{total_seconds // 3600:02d}:{(total_seconds // 60) % 60:02d}:{total_seconds % 60:02d}:{ff:02d}"


def grab_clip_frame(track_index: int, clip_index: int) -> Optional[Dict[str, Any]]:
    """Moves the playhead to the middle of a clip and returns that frame's thumbnail.

    Resolve only renders thumbnails of the clip under the playhead on the Color page,
    so this opens the Color page first. Returns None when Resolve is unreachable.
    """
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
    try:
        from ..connection import get_resolve
        resolve = get_resolve()
        if resolve and hasattr(resolve, "OpenPage"):
            resolve.OpenPage("color")
        mid = (int(clip.GetStart()) + int(clip.GetEnd())) // 2
        fps = timeline.GetSetting("timelineFrameRate") or 24
        if hasattr(timeline, "SetCurrentTimecode"):
            timeline.SetCurrentTimecode(frames_to_timecode(mid, fps))
    except Exception as e:
        logger.warning(f"Could not move playhead to clip {clip_index}: {e}")
    if hasattr(timeline, "GetCurrentClipThumbnailImage"):
        return timeline.GetCurrentClipThumbnailImage()
    return None
