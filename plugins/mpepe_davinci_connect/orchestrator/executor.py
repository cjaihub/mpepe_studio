"""executor — Tool-calling loop with step-by-step plan execution and streaming."""
import logging
import queue
import threading
import uuid
from typing import Dict, Any, Generator

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

def get_task_bus(task_id: str) -> queue.Queue:
    with _bus_lock:
        return _event_bus.get(task_id)

def remove_task_bus(task_id: str):
    with _bus_lock:
        _event_bus.pop(task_id, None)

class Executor:
    def __init__(self, bridge_host: str = "localhost", bridge_port: int = 50051):
        self.bridge_host = bridge_host
        self.bridge_port = bridge_port
        
        # State for step confirmations: (task_id, step_index) -> queue.Queue
        self._confirmations: Dict[tuple, queue.Queue] = {}
        self._conf_lock = threading.Lock()
        
        self._init_agents()

    def confirm_step(self, task_id: str, step_index: int):
        with self._conf_lock:
            q = self._confirmations.get((task_id, step_index))
            if q:
                q.put("confirm")

    def reject_step(self, task_id: str, step_index: int, reason: str):
        with self._conf_lock:
            q = self._confirmations.get((task_id, step_index))
            if q:
                if reason == "skip":
                    q.put("skip")
                else:
                    q.put("abort")

    def _wait_for_confirmation(self, task_id: str, step_index: int) -> str:
        q = queue.Queue()
        with self._conf_lock:
            self._confirmations[(task_id, step_index)] = q
            
        # Block until confirm_step or reject_step puts a string in the queue
        decision = q.get()
        
        with self._conf_lock:
            self._confirmations.pop((task_id, step_index), None)
            
        return decision

    def _init_agents(self):
        """Lazily imports all agents to avoid circular deps at startup."""
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

        class UserAgent:
            def __init__(self, bridge_client):
                pass
            def execute_task(self, step):
                return "User completed the task manually."

        class OSAgent:
            def __init__(self, bridge_client):
                pass
            def execute_task(self, step):
                import subprocess
                task_desc = step.get("task", "").lower()
                if "launch" in task_desc or "open" in task_desc:
                    try:
                        # Assuming default installation path for DaVinci Resolve on Windows
                        subprocess.Popen(r"C:\Program Files\Blackmagic Design\DaVinci Resolve\Resolve.exe")
                        return "Launched DaVinci Resolve."
                    except Exception as e:
                        return f"Failed to launch DaVinci Resolve: {e}"
                return "Unknown OS task."

        bridge_client = None  # gRPC client stub — wired when bridge connects

        self._agents = {
            "Color Scientist": ColorScientist(bridge_client),
            "Tracking":        TrackingAgent(bridge_client),
            "Match":           MatchAgent(bridge_client),
            "Skin":            SkinAgent(bridge_client),
            "Quality":         QualityAgent(bridge_client),
            "Enhance":         EnhanceAgent(bridge_client),
            "Audio":           AudioAgent(bridge_client),
            "HDR":             HdrAgent(bridge_client),
            "Memory":          MemoryAgent(bridge_client),
            "Render":          RenderAgent(bridge_client),
            "Film":            FilmAgent(bridge_client),
            "Cloud":           CloudAgent(bridge_client),
            "Skill":           SkillAgent(bridge_client),
            "Reference":       ReferenceAgent(),
            "LUT":             LutAgent(),
            "Auditor":         AuditorAgent(),
            "User":            UserAgent(bridge_client),
            "OS":              OSAgent(bridge_client),
        }

    def _emit(self, task_bus: queue.Queue, event: dict, task_id: str = ""):
        """Push an event onto the bus so the gRPC stream can dequeue it."""
        if task_id:
            with _status_lock:
                if event.get("status") == "__DONE__":
                    _active_tasks_status.pop(task_id, None)
                else:
                    _active_tasks_status[task_id] = event
                    
        if task_bus:
            task_bus.put(event)

    def execute_plan(self, plan: Dict[str, Any], task_id: str = "") -> Dict[str, Any]:
        """
        Executes a Director plan step-by-step.
        For each step it pushes a RUNNING event, then a DONE or ERROR event
        onto the task bus identified by task_id so the Flutter Task Queue
        panel receives live updates via the StreamPlanEvents RPC.
        """
        if plan.get("status") != "success":
            return {"status": "error", "message": "Invalid plan."}

        steps = plan.get("plan", [])
        total = len(steps)
        task_bus = get_task_bus(task_id) if task_id else None

        results = []
        for idx, step in enumerate(steps):
            agent_name = step.get("agent", "")
            task_desc  = step.get("task", "")
            agent = self._agents.get(agent_name)

            # Emit RUNNING or WAITING_CONFIRMATION
            requires_confirmation = step.get("requires_confirmation", False)
            
            if requires_confirmation:
                self._emit(task_bus, {
                    "task_id": task_id,
                    "step_index": idx + 1,
                    "total_steps": total,
                    "agent": agent_name,
                    "task_description": task_desc,
                    "status": "WAITING_CONFIRMATION",
                    "detail": "Awaiting user approval.",
                }, task_id)
                
                # Block until confirmed or rejected
                decision = self._wait_for_confirmation(task_id, idx + 1)
                
                if decision == "abort":
                    logger.info(f"Step {idx + 1} aborted by user.")
                    self._emit(task_bus, {
                        "task_id": task_id, "step_index": idx + 1, "total_steps": total,
                        "agent": agent_name, "task_description": task_desc,
                        "status": "ERROR", "detail": "Aborted by user.",
                    }, task_id)
                    results.append({"step": step, "result": "error: aborted"})
                    break # Stop entire plan on abort
                    
                elif decision == "skip":
                    logger.info(f"Step {idx + 1} skipped by user.")
                    self._emit(task_bus, {
                        "task_id": task_id, "step_index": idx + 1, "total_steps": total,
                        "agent": agent_name, "task_description": task_desc,
                        "status": "DONE", "detail": "Skipped.",
                    }, task_id)
                    results.append({"step": step, "result": "skipped"})
                    continue
            
            self._emit(task_bus, {
                "task_id": task_id,
                "step_index": idx + 1,
                "total_steps": total,
                "agent": agent_name,
                "task_description": task_desc,
                "status": "RUNNING",
                "detail": "",
            }, task_id)

            if not agent:
                detail = f"Unknown agent: {agent_name}"
                logger.error(detail)
                self._emit(task_bus, {
                    "task_id": task_id, "step_index": idx + 1, "total_steps": total,
                    "agent": agent_name, "task_description": task_desc,
                    "status": "ERROR", "detail": detail,
                }, task_id)
                results.append({"step": step, "result": f"error: {detail}"})
                continue

            logger.info(f"Executing [{agent_name}] {task_desc}")
            try:
                result = agent.execute_task(step)
                import json
                detail_str = json.dumps(result) if isinstance(result, dict) else str(result)
                self._emit(task_bus, {
                    "task_id": task_id, "step_index": idx + 1, "total_steps": total,
                    "agent": agent_name, "task_description": task_desc,
                    "status": "DONE", "detail": detail_str,
                }, task_id)
                results.append({"step": step, "result": result})
            except Exception as e:
                detail = str(e)
                logger.error(f"Agent {agent_name} failed: {detail}")
                self._emit(task_bus, {
                    "task_id": task_id, "step_index": idx + 1, "total_steps": total,
                    "agent": agent_name, "task_description": task_desc,
                    "status": "ERROR", "detail": detail,
                }, task_id)
                results.append({"step": step, "result": f"error: {detail}"})

        # Sentinel: tells the streaming consumer to close the stream
        self._emit(task_bus, {"status": "__DONE__"}, task_id)
        remove_task_bus(task_id)
        
        # Cleanup any pending confirmations for this task
        with self._conf_lock:
            keys_to_delete = [k for k in self._confirmations.keys() if k[0] == task_id]
            for k in keys_to_delete:
                del self._confirmations[k]
                
        return {"status": "done", "results": results}


