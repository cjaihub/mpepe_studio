"""node_tools — Node graph management (enable, disable, label, reorder, cache)."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.node")

def _get_clip(project, track_index: int, clip_index: int):
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return None
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return None
    return items[clip_index - 1]

def enable_node(track_index: int, clip_index: int, node_index: int) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if not clip:
        return False
    if hasattr(clip, "SetNodeEnabled"):
        return clip.SetNodeEnabled(node_index, True)
    return False

def disable_node(track_index: int, clip_index: int, node_index: int) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if not clip:
        return False
    if hasattr(clip, "SetNodeEnabled"):
        return clip.SetNodeEnabled(node_index, False)
    return False

def set_node_label(track_index: int, clip_index: int, node_index: int, label: str) -> bool:
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if not clip:
        return False
    if hasattr(clip, "SetNodeLabel"):
        return clip.SetNodeLabel(node_index, label)
    return False

def reorder_nodes(track_index: int, clip_index: int, node_a: int, node_b: int) -> bool:
    """Swap nodes at positions node_a and node_b."""
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if not clip:
        return False
    if hasattr(clip, "ReorderNode"):
        return clip.ReorderNode(node_a, node_b)
    return False

def get_node_graph(track_index: int, clip_index: int) -> list:
    """Retrieve all nodes for a given clip."""
    _, project = get_current_project()
    if not project:
        return []
    clip = _get_clip(project, track_index, clip_index)
    if not clip:
        return []
        
    nodes = []
    if hasattr(clip, "GetNumNodes"):
        num_nodes = clip.GetNumNodes()
        # Assume 1-indexed for nodes in Resolve API
        for i in range(1, num_nodes + 1):
            label = ""
            if hasattr(clip, "GetNodeLabel"):
                label = clip.GetNodeLabel(i)
                if not label:
                    label = f"Node {i}"
            else:
                label = f"Node {i}"
            
            # Since Resolve API does not expose GetNodeEnabled reliably in all versions, 
            # we default to True for this visualizer.
            nodes.append({
                "index": i,
                "label": label,
                "is_enabled": True
            })
    return nodes
