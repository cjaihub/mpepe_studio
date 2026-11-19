"""enhance_tools — Speed, dynamic zoom, transform, crop, SuperScale properties."""
import logging
from typing import Optional
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.enhance")

def _set_property(track_index: int, clip_index: int, props: dict) -> bool:
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
    results = []
    for key, value in props.items():
        if hasattr(clip, "SetProperty"):
            results.append(clip.SetProperty(key, value))
    return all(results)

def set_speed(track_index: int, clip_index: int, speed: float,
              retime_process: str = "OpticalFlow") -> bool:
    """Set clip speed (1.0 = normal, 2.0 = double speed, 0.5 = half speed)."""
    return _set_property(track_index, clip_index, {
        "Speed": str(speed),
        "RetimeProcess": retime_process,
    })

def set_dynamic_zoom(track_index: int, clip_index: int,
                     enabled: bool, mode: Optional[str] = None) -> bool:
    props = {"DynamicZoomEnable": "1" if enabled else "0"}
    if mode:
        props["DynamicZoomMode"] = mode
    return _set_property(track_index, clip_index, props)

def set_transform(track_index: int, clip_index: int, **kwargs) -> bool:
    """Set transform properties: Pan, Tilt, ZoomX, ZoomY, Rotation, Pitch, Yaw."""
    allowed = {"Pan", "Tilt", "ZoomX", "ZoomY", "Rotation", "AnchorPointX", "AnchorPointY",
               "Pitch", "Yaw"}
    props = {k: str(v) for k, v in kwargs.items() if k in allowed}
    return _set_property(track_index, clip_index, props)

def set_crop(track_index: int, clip_index: int,
             left: float = 0, right: float = 0,
             top: float = 0, bottom: float = 0) -> bool:
    return _set_property(track_index, clip_index, {
        "CropLeft": str(left), "CropRight": str(right),
        "CropTop": str(top), "CropBottom": str(bottom),
    })
