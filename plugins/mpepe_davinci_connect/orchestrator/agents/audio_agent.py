"""audio_agent — voice isolation, transcription and audio classification on a clip."""
import logging

from bridge.tools.audio_tools import set_voice_isolation, transcribe_audio, audio_classification
from .agent_base import AgentBase, step_target, fail, from_bool

logger = logging.getLogger("cj_grader.agents.audio")


class AudioAgent(AgentBase):
    name = "Audio"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "").lower()
        params = task.get("params", {}) or {}
        t = step_target(task)
        track, clip = t["track_index"], t["clip_index"]
        logger.info(f"Audio Agent: {task_name}")

        if "voice" in task_name or "isolat" in task_name or "dialog" in task_name:
            state = bool(params.get("enabled", True))
            return from_bool(set_voice_isolation(track, clip, state),
                             f"Voice isolation {'on' if state else 'off'}.",
                             "Voice isolation unavailable (needs Resolve Studio 20+).")
        if "transcri" in task_name or "caption" in task_name or "subtitle" in task_name:
            return from_bool(transcribe_audio(track, clip), "Transcription finished.",
                             "Transcription unavailable on this Resolve build.")
        if "classif" in task_name:
            return from_bool(audio_classification(track, clip), "Audio classified.",
                             "Audio classification unavailable on this Resolve build.")
        return fail(f"Unknown task for Audio: {task.get('task', '')}")
