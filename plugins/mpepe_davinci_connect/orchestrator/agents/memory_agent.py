"""memory_agent — grade versions, grade history and per-project preferences."""
import datetime
import json
import logging

from bridge.tools.version_tools import add_version, load_version, list_versions
from orchestrator.memory_store import get_memory_store
from .agent_base import AgentBase, step_target, ok, fail

logger = logging.getLogger("cj_grader.agents.memory")


class MemoryAgent(AgentBase):
    name = "Memory"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)
        self.store = get_memory_store()

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "").lower()
        params = task.get("params", {}) or {}
        t = step_target(task)
        project_id = params.get("project_id", "default_project")
        logger.info(f"Memory Agent: {task_name}")

        if "save_preference" in task_name or "remember" in task_name:
            key, value = params.get("key"), params.get("value")
            if not key or value is None:
                return fail("Missing key or value")
            self.store.save_preference(project_id, key, value)
            return ok(f"Remembered {key}.")

        if "get_preference" in task_name or "recall" in task_name:
            key = params.get("key")
            if not key:
                return fail("Missing key")
            return ok(f"{key} = {self.store.get_preference(project_id, key)}",
                      value=self.store.get_preference(project_id, key))

        if "load" in task_name and "version" in task_name:
            name = params.get("version_name", "")
            return (ok(f"Loaded version {name}.") if name and load_version(t["track_index"], t["clip_index"], name)
                    else fail(f"Could not load version '{name}'."))

        if "list" in task_name and "version" in task_name:
            versions = list_versions(t["track_index"], t["clip_index"])
            return ok(f"{len(versions)} version(s).", detail=f"[VERSIONS] {json.dumps(versions)}")

        if "version" in task_name or "snapshot" in task_name or "save grade" in task_name:
            name = params.get("version_name") or f"CJ_{datetime.datetime.now():%Y%m%d_%H%M%S}"
            return (ok(f"Saved grade version {name}.") if add_version(t["track_index"], t["clip_index"], name)
                    else fail("Resolve could not add a grade version."))

        if "history" in task_name or "ledger" in task_name:
            entries = self.store.get_history(t["timeline_id"], t["track_index"], t["clip_index"])
            return ok(f"{len(entries)} grade action(s) on this clip.",
                      detail=f"[HISTORY] {json.dumps(entries, default=str)}", entries=entries)

        return fail(f"Unknown task for Memory: {task.get('task', '')}")
