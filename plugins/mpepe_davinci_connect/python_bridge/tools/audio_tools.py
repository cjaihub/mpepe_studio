"""audio_tools — Voice isolation, transcription, audio classification."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.audio")

def _get_clip(project, track_index: int, clip_index: int):
    timeline = project.GetCurrentTimeline()
    if not timeline:
        return None
    items = timeline.GetItemListInTrack("video", track_index)
    if not items or clip_index < 1 or clip_index > len(items):
        return None
    return items[clip_index - 1]

def set_voice_isolation(track_index: int, clip_index: int, state: bool) -> bool:
    """Enables or disables AI voice isolation on a clip (Studio 21+)."""
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "SetVoiceIsolationState"):
        return clip.SetVoiceIsolationState(state)
    logger.warning("SetVoiceIsolationState not available on this Resolve build.")
    return False

def transcribe_audio(track_index: int, clip_index: int) -> bool:
    """Runs AI transcription on the clip audio."""
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "TranscribeAudio"):
        return clip.TranscribeAudio()
    return False

def audio_classification(track_index: int, clip_index: int) -> bool:
    """Runs AI audio classification on the clip."""
    _, project = get_current_project()
    if not project:
        return False
    clip = _get_clip(project, track_index, clip_index)
    if clip and hasattr(clip, "PerformAudioClassification"):
        return clip.PerformAudioClassification()
    return False
