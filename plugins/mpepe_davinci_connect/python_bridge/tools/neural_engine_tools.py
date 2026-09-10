import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.neural")

def create_magic_mask(timeline_id: str, track_index: int, clip_index: int, mode: str) -> bool:
    """Creates a magic mask on a clip."""
    resolve, project = get_current_project()
    if not project:
        return False
        
    from bridge.capability_probe import CapabilityProbe
    probe = CapabilityProbe(resolve)
    caps = probe.get_capabilities()
    
    # Check if we have studio / magic mask
    mm_cap = caps["features"].get("magic_mask", {})
    if not mm_cap.get("available"):
        logger.warning("Magic Mask requires DaVinci Resolve Studio.")
        return False
        
    timeline = project.GetCurrentTimeline()
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index > len(items):
        return False
        
    clip = items[clip_index - 1]
    
    if hasattr(clip, "CreateMagicMask"):
        # If mode is automated but API is guided-only, we might fail or mock it
        if mode == "automated" and mm_cap.get("mode") == "guided":
            logger.warning("Automated Magic Mask requested but only Guided is available. Falling back to Guided.")
            mode = "guided"
        return clip.CreateMagicMask(mode)
    
    logger.error("CreateMagicMask is not supported on this version of Resolve.")
    return False

def stabilize(timeline_id: str, track_index: int, clip_index: int) -> bool:
    """Runs stabilization on a clip."""
    _, project = get_current_project()
    if not project:
        return False
        
    timeline = project.GetCurrentTimeline()
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
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index > len(items):
        return False
        
    clip = items[clip_index - 1]
    if hasattr(clip, "SmartReframe"):
        return clip.SmartReframe()
    return False
