"""timeline_tools — Timeline-wide clip iteration and metadata for multi-clip planning."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.timeline")


def get_timeline_info(timeline_id: str = "") -> dict:
    """Returns metadata about the current timeline: name, frame rate, resolution, clip count."""
    _, project = get_current_project()
    if not project:
        return {"error": "No active project"}

    timeline = project.GetCurrentTimeline()
    if not timeline:
        return {"error": "No active timeline"}

    return {
        "name": timeline.GetName(),
        "frame_rate": timeline.GetSetting("timelineFrameRate") or "24",
        "resolution_x": timeline.GetSetting("timelineResolutionWidth") or "1920",
        "resolution_y": timeline.GetSetting("timelineResolutionHeight") or "1080",
        "video_track_count": timeline.GetTrackCount("video"),
        "audio_track_count": timeline.GetTrackCount("audio"),
        "start_frame": timeline.GetStartFrame(),
        "end_frame": timeline.GetEndFrame(),
    }


def get_all_clips(timeline_id: str = "", track_index: int = 1) -> list:
    """Returns a list of all clips on a video track with index/name/duration info."""
    _, project = get_current_project()
    if not project:
        return []

    timeline = project.GetCurrentTimeline()
    if not timeline:
        return []

    items = timeline.GetItemListInTrack("video", track_index)
    if not items:
        return []

    clips = []
    for idx, item in enumerate(items, start=1):
        clip_info = {
            "clip_index": idx,
            "name": item.GetName() if hasattr(item, "GetName") else f"Clip {idx}",
            "duration": item.GetDuration() if hasattr(item, "GetDuration") else 0,
            "start": item.GetStart() if hasattr(item, "GetStart") else 0,
            "end": item.GetEnd() if hasattr(item, "GetEnd") else 0,
            "track_index": track_index,
        }
        # Check if clip has existing color versions
        if hasattr(item, "GetVersionNameList"):
            versions = item.GetVersionNameList(0) or []
            clip_info["version_count"] = len(versions)
        clips.append(clip_info)

    return clips


def get_selected_clips(timeline_id: str = "") -> list:
    """Returns only the currently selected clips (Resolve 21.0.4+)."""
    _, project = get_current_project()
    if not project:
        return []

    timeline = project.GetCurrentTimeline()
    if not timeline:
        return []

    if not hasattr(timeline, "GetSelectedClips"):
        logger.warning("GetSelectedClips not available — requires Resolve 21.0.4+")
        return []

    selected = timeline.GetSelectedClips()
    if not selected:
        return []

    return [
        {
            "clip_index": i + 1,
            "name": clip.GetName() if hasattr(clip, "GetName") else f"Clip {i+1}",
        }
        for i, clip in enumerate(selected)
    ]
