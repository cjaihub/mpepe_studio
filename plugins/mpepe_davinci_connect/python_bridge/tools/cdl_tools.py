import logging
from ..connection import get_current_project
from .version_tools import take_snapshot

logger = logging.getLogger("cj_grader.cdl_tools")

def set_cdl(timeline_id: str, track_index: int, clip_index: int, node_index: int,
            slope: dict, offset: dict, power: dict, saturation: float,
            append_new_node: bool = False, snapshot_label: str = "pre_cdl") -> dict:
    """
    Sets CDL parameters on a specific node of a clip.
    ALWAYS takes a Resolve version snapshot first — non-destructive by contract.

    Returns a dict:
      { "success": bool, "snapshot": "<version_name or empty>" }
    """
    # STEP 1: Snapshot (non-destructive gate). Proceeds even if snapshot fails
    # so the operation is never blocked, but failure is logged and returned.
    snapshot_name = take_snapshot(track_index, clip_index, label=snapshot_label)

    _, project = get_current_project()
    if not project:
        return {"success": False, "snapshot": snapshot_name}

    timeline = (
        project.GetTimelineById(timeline_id)
        if hasattr(project, "GetTimelineById")
        else project.GetCurrentTimeline()
    )
    if not timeline:
        return {"success": False, "snapshot": snapshot_name}

    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index > len(items):
        return {"success": False, "snapshot": snapshot_name}

    clip = items[clip_index - 1]

    slope_d  = {k.lower(): v for k, v in slope.items()}
    offset_d = {k.lower(): v for k, v in offset.items()}
    power_d  = {k.lower(): v for k, v in power.items()}

    cdl_map = {
        "Slope":      [slope_d.get('r', 1.0),  slope_d.get('g', 1.0),  slope_d.get('b', 1.0),  slope_d.get('y', 1.0)],
        "Offset":     [offset_d.get('r', 0.0), offset_d.get('g', 0.0), offset_d.get('b', 0.0), offset_d.get('y', 0.0)],
        "Power":      [power_d.get('r', 1.0),  power_d.get('g', 1.0),  power_d.get('b', 1.0),  power_d.get('y', 1.0)],
        "Saturation": [saturation, saturation, saturation, saturation],
    }

    if append_new_node:
        try:
            if hasattr(clip, "AddCorrectorNode"):
                clip.AddCorrectorNode()
            elif hasattr(clip, "AddNode"):
                clip.AddNode()
        except Exception as e:
            logger.warning(f"Could not append new node: {e}")

    if hasattr(clip, "SetCDL"):
        success = clip.SetCDL(cdl_map)
        return {"success": success, "snapshot": snapshot_name}

    return {"success": False, "snapshot": snapshot_name}

