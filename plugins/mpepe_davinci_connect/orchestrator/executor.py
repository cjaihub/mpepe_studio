"""executor — runs Director plans step by step, streaming events to the UI."""
import json
import logging
import queue
import subprocess
import sys
import threading
from typing import Any, Dict, Optional

logger = logging.getLogger("cj_grader.executor")

# Global event bus: task_id -> Queue[dict]
# The gRPC streaming servicer consumes from here.
_event_bus: Dict[str, queue.Queue] = {}
_bus_lock = threading.Lock()

_active_tasks_status: Dict[str, dict] = {}
_status_lock = threading.Lock()


def get_active_tasks() -> Dict[str, dict]:
    with _status_lock:
        return dict(_active_tasks_status)


def create_task_bus(task_id: str) -> queue.Queue:
    q: queue.Queue = queue.Queue()
    with _bus_lock:
        _event_bus[task_id] = q
    return q


def get_task_bus(task_id: str) -> Optional[queue.Queue]:
    with _bus_lock:
        return _event_bus.get(task_id)


def remove_task_bus(task_id: str):
    with _bus_lock:
        _event_bus.pop(task_id, None)


# Every spelling the Director, the live servicer or older clients use -> registry key.
AGENT_ALIASES = {
    "colorscientist": "Color Scientist", "color": "Color Scientist", "cdl": "Color Scientist",
    "tracking": "Tracking", "tracker": "Tracking",
    "match": "Match", "matching": "Match",
    "skin": "Skin", "beauty": "Skin",
    "quality": "Quality", "noisereduction": "Quality",
    "enhance": "Enhance",
    "audio": "Audio",
    "hdr": "HDR", "dolbyvision": "HDR",
    "memory": "Memory", "version": "Memory",
    "render": "Render", "deliver": "Render",
    "film": "Film", "filmlook": "Film",
    "cloud": "Cloud",
    "skill": "Skill", "skillapply": "Skill", "skills": "Skill",
    "reference": "Reference", "referencematch": "Reference",
    "lut": "LUT",
    "auditor": "Auditor", "audit": "Auditor",
    "lookprofile": "LookProfile", "look": "LookProfile",
    "user": "User", "manual": "User",
    "os": "OS", "system": "OS",
}

# Agents that act on one clip; with scope "timeline" they run once per clip on the track.
PER_CLIP_AGENTS = {"Color Scientist", "Skin", "Quality", "Enhance", "Audio", "HDR", "Film",
                   "Skill", "LUT", "Tracking"}


def canonical_agent_name(name: str) -> str:
    key = "".join(ch for ch in (name or "").lower() if ch.isalnum())
    if key.endswith("agent") and key not in AGENT_ALIASES:
        key = key[:-len("agent")]
    return AGENT_ALIASES.get(key, name)


class UserAgent:
    """A step the user performs by hand; the plan waits for their confirmation first."""

    def execute_task(self, step):
        return {"status": "success", "message": "User completed the task manually."}


class OSAgent:
    """Opens or closes DaVinci Resolve on macOS, Windows or Linux."""

    def execute_task(self, step):
        task = step.get("task", "").lower()
        try:
            if "close" in task or "quit" in task:
                from bridge.connection import get_resolve
                resolve = get_resolve()
                if resolve and hasattr(resolve, "Quit"):
                    resolve.Quit()
                    return {"status": "success", "message": "Closed DaVinci Resolve."}
                return {"status": "error", "message": "DaVinci Resolve is not running."}
            if "launch" in task or "open" in task or "start" in task:
                if sys.platform == "darwin":
                    subprocess.Popen(["open", "-a", "DaVinci Resolve"])
                elif sys.platform.startswith("win"):
                    subprocess.Popen([r"C:\Program Files\Blackmagic Design\DaVinci Resolve\Resolve.exe"])
                else:
                    subprocess.Popen(["/opt/resolve/bin/resolve"])
                return {"status": "success", "message": "Launching DaVinci Resolve."}
        except Exception as e:
            return {"status": "error", "message": f"OS task failed: {e}"}
        return {"status": "error", "message": f"Unknown OS task: {step.get('task', '')}"}


def _result_event(result: Any):
    """Maps an agent result to (event status, detail text)."""
    if not isinstance(result, dict):
        return "DONE", str(result)
    status = str(result.get("status", "success")).lower()
    message = result.get("message", "")
    if status == "error":
        return "ERROR", message or "Agent reported an error."
    if status == "skipped":
        return "DONE", f"Skipped: {message}"
    if status == "guided":
        return "DONE", f"[GUIDED] {message}"
    # Tagged payloads ("[GRADE_PARAMS] {...}") are parsed by the UI, so send them untouched.
    return "DONE", result.get("detail") or message or json.dumps(result, default=str)


class Executor:
    def __init__(self, bridge_host: str = "localhost", bridge_port: int = 50051):
        self.bridge_host = bridge_host
        self.bridge_port = bridge_port

        # State for step confirmations: (task_id, step_index) -> queue.Queue
        self._confirmations: Dict[tuple, queue.Queue] = {}
        self._conf_lock = threading.Lock()

        self._init_agents()

    # ── Confirmations ────────────────────────────────────────────────────

    def confirm_step(self, task_id: str, step_index: int):
        with self._conf_lock:
            q = self._confirmations.get((task_id, step_index))
        if q:
            q.put("confirm")

    def reject_step(self, task_id: str, step_index: int, reason: str):
        with self._conf_lock:
            q = self._confirmations.get((task_id, step_index))
        if q:
            q.put("skip" if reason == "skip" else "abort")

    def _wait_for_confirmation(self, task_id: str, step_index: int, timeout: float = 1800) -> str:
        q: queue.Queue = queue.Queue()
        with self._conf_lock:
            self._confirmations[(task_id, step_index)] = q
        try:
            return q.get(timeout=timeout)
        except queue.Empty:
            logger.warning(f"Step {step_index} of {task_id} not confirmed within {timeout:.0f}s; aborting.")
            return "abort"
        finally:
            with self._conf_lock:
                self._confirmations.pop((task_id, step_index), None)

    # ── Agents ───────────────────────────────────────────────────────────

    def _init_agents(self):
        """Imports agents lazily so the bridge can start before optional deps load."""
        from .agents.color_scientist import ColorScientist
        from .agents.tracking_agent import TrackingAgent
        from .agents.match_agent import MatchAgent
        from .agents.skin_agent import SkinAgent
        from .agents.quality_agent import QualityAgent
        from .agents.enhance_agent import EnhanceAgent
        from .agents.audio_agent import AudioAgent
        from .agents.hdr_agent import HdrAgent
        from .agents.memory_agent import MemoryAgent
        from .agents.render_agent import RenderAgent
        from .agents.film_agent import FilmAgent
        from .agents.cloud_agent import CloudAgent
        from .agents.skill_agent import SkillAgent
        from .agents.reference_agent import ReferenceAgent
        from .agents.lut_agent import LutAgent
        from .agents.auditor_agent import AuditorAgent
        from .agents.look_profile_agent import LookProfileAgent

        self._agents = {
            "Color Scientist": ColorScientist(),
            "Tracking":        TrackingAgent(),
            "Match":           MatchAgent(),
            "Skin":            SkinAgent(),
            "Quality":         QualityAgent(),
            "Enhance":         EnhanceAgent(),
            "Audio":           AudioAgent(),
            "HDR":             HdrAgent(),
            "Memory":          MemoryAgent(),
            "Render":          RenderAgent(),
            "Film":            FilmAgent(),
            "Cloud":           CloudAgent(),
            "Skill":           SkillAgent(),
            "Reference":       ReferenceAgent(),
            "LUT":             LutAgent(),
            "Auditor":         AuditorAgent(),
            "LookProfile":     LookProfileAgent(),
            "User":            UserAgent(),
            "OS":              OSAgent(),
        }

    @property
    def agent_names(self):
        return list(self._agents)

    def get_agent(self, name: str):
        return self._agents.get(canonical_agent_name(name))

    def _run_step(self, agent_name: str, agent, step: dict) -> Any:
        """Runs one step; timeline-scoped per-clip steps fan out over every clip on the track."""
        if step.get("scope") != "timeline" or agent_name not in PER_CLIP_AGENTS:
            return agent.execute_task(step)

        from bridge.tools.timeline_tools import get_all_clips
        clips = get_all_clips(step.get("timeline_id", ""), int(step.get("track_index") or 1))
        if not clips:
            return {"status": "error", "message": "No clips found on the timeline."}
        done, failures, last = 0, [], None
        for clip in clips:
            last = agent.execute_task({**step, "clip_index": clip["clip_index"], "scope": "clip"})
            status = str(last.get("status", "success")).lower() if isinstance(last, dict) else "success"
            if status == "error":
                failures.append(f"clip {clip['clip_index']}: {last.get('message', '')}")
            else:
                done += 1
        message = f"Applied to {done}/{len(clips)} clips."
        if failures:
            message += " Failed: " + "; ".join(failures[:5])
        result = {"status": "success" if done else "error", "message": message}
        if isinstance(last, dict) and last.get("detail"):
            result["detail"] = last["detail"]
        return result

    def _emit(self, task_bus: Optional[queue.Queue], event: dict, task_id: str = ""):
        """Push an event onto the bus so the gRPC stream can dequeue it."""
        if task_id:
            with _status_lock:
                if event.get("status") == "__DONE__":
                    _active_tasks_status.pop(task_id, None)
                else:
                    _active_tasks_status[task_id] = event
        if task_bus:
            task_bus.put(event)

    # ── Plans ────────────────────────────────────────────────────────────

    def execute_plan(self, plan: Any, task_id: str = "", auto_confirm: bool = False) -> Dict[str, Any]:
        """
        Executes a Director plan step-by-step. Accepts the Director's
        ``{"status": "success", "plan": [...]}`` or a bare list of steps.

        Each step emits RUNNING (or WAITING_CONFIRMATION first), then DONE or
        ERROR onto the task bus for ``task_id``. ``auto_confirm`` skips the
        confirmation wait for callers with no way to confirm (e.g. phone NLP).
        """
        from .agents.agent_base import set_progress_sink

        if isinstance(plan, list):
            plan = {"status": "success", "plan": plan}
        if not isinstance(plan, dict) or plan.get("status") != "success":
            return {"status": "error", "message": "Invalid plan."}

        steps = plan.get("plan", [])
        total = len(steps)
        task_bus = get_task_bus(task_id) if task_id else None
        results = []

        for idx, step in enumerate(steps):
            # Older callers used "action"/"parameters"
            if "task" not in step and "action" in step:
                step = {**step, "task": step["action"]}
            if "params" not in step and "parameters" in step:
                step = {**step, "params": step["parameters"]}

            agent_name = canonical_agent_name(step.get("agent", ""))
            task_desc = step.get("task", "")
            agent = self._agents.get(agent_name)
            base = {"task_id": task_id, "step_index": idx + 1, "total_steps": total,
                    "agent": agent_name, "task_description": task_desc}

            if step.get("requires_confirmation", False) and not auto_confirm:
                self._emit(task_bus, {**base, "status": "WAITING_CONFIRMATION",
                                      "detail": "Awaiting user approval."}, task_id)
                decision = self._wait_for_confirmation(task_id, idx + 1)
                if decision == "abort":
                    logger.info(f"Step {idx + 1} aborted by user.")
                    self._emit(task_bus, {**base, "status": "ERROR", "detail": "Aborted by user."}, task_id)
                    results.append({"step": step, "result": "error: aborted"})
                    break
                if decision == "skip":
                    logger.info(f"Step {idx + 1} skipped by user.")
                    self._emit(task_bus, {**base, "status": "DONE", "detail": "Skipped."}, task_id)
                    results.append({"step": step, "result": "skipped"})
                    continue

            self._emit(task_bus, {**base, "status": "RUNNING", "detail": ""}, task_id)

            if not agent:
                detail = f"Unknown agent: {step.get('agent', '')}. Known: {', '.join(self._agents)}"
                logger.error(detail)
                self._emit(task_bus, {**base, "status": "ERROR", "detail": detail}, task_id)
                results.append({"step": step, "result": f"error: {detail}"})
                continue

            logger.info(f"Executing [{agent_name}] {task_desc}")
            set_progress_sink(lambda msg, detail, b=base: self._emit(
                task_bus, {**b, "status": "RUNNING", "detail": detail or msg}, task_id))
            try:
                result = self._run_step(agent_name, agent, step)
                status, detail = _result_event(result)
                self._emit(task_bus, {**base, "status": status, "detail": detail}, task_id)
                results.append({"step": step, "result": result})
            except Exception as e:
                logger.exception(f"Agent {agent_name} failed")
                self._emit(task_bus, {**base, "status": "ERROR", "detail": str(e)}, task_id)
                results.append({"step": step, "result": f"error: {e}"})
            finally:
                set_progress_sink(None)

        # Sentinel: tells the streaming consumer to close the stream
        self._emit(task_bus, {"status": "__DONE__"}, task_id)
        remove_task_bus(task_id)

        with self._conf_lock:
            for k in [k for k in self._confirmations if k[0] == task_id]:
                del self._confirmations[k]

        return {"status": "done", "results": results}
