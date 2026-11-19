import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.neural")

def create_magic_mask(timeline_id: str, track_index: int, clip_index: int, mode: str) -> bool:
    """Creates a magic mask on a clip."""
    _, project = get_current_project()
    if not project:
        return False

    from ..capability_probe import current_capabilities
    caps = current_capabilities()
    
    # Check if we have studio / magic mask
    mm_cap = caps["features"].get("magic_mask", {})
    if not mm_cap.get("available"):
        logger.warning("Magic Mask requires DaVinci Resolve Studio.")
        return False
        
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return False
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index > len(items):
        return False
        
    clip = items[clip_index - 1]
    
    if hasattr(clip, "CreateMagicMask"):
        # Resolve tracks the mask Forward ("F"), Backward ("B") or both ("BI").
        if mode not in ("F", "B", "BI"):
            mode = "F"
        return bool(clip.CreateMagicMask(mode))
    
    logger.error("CreateMagicMask is not supported on this version of Resolve.")
    return False

def stabilize(timeline_id: str, track_index: int, clip_index: int) -> bool:
    """Runs stabilization on a clip."""
    _, project = get_current_project()
    if not project:
        return False
        
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return False
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index > len(items):
        return False
        
    clip = items[clip_index - 1]
    if hasattr(clip, "Stabilize"):
        return clip.Stabilize()
    return False

def smart_reframe(timeline_id: str, track_index: int, clip_index: int) -> bool:
    """Runs smart reframe on a clip."""
    _, project = get_current_project()
    if not project:
        return False
        
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return False
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index > len(items):
        return False
        
    clip = items[clip_index - 1]
    if hasattr(clip, "SmartReframe"):
        return clip.SmartReframe()
    return False
