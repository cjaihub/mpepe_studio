import logging
from orchestrator.memory_store import get_memory_store

logger = logging.getLogger("cj_grader.agents.memory")

class MemoryAgent:
    def __init__(self, bridge_client):
        self.bridge = bridge_client
        self.store = get_memory_store()

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "")
        params = task.get("params", {})
        logger.info(f"Memory Agent: {task_name}")

        if "version" in task_name.lower():
            name = params.get("version_name", "AI Grade 1")
            return {"status": "success", "action": f"VersionAdded({name})"}
        elif "history" in task_name.lower() or "ledger" in task_name.lower():
            return {"status": "success", "action": "LedgerQueried", "entries": []}
        elif "save_preference" in task_name.lower():
            key = params.get("key")
            value = params.get("value")
            project_id = params.get("project_id", "default_project")
            if key and value:
                self.store.save_preference(project_id, key, value)
                return {"status": "success", "action": "PreferenceSaved"}
            return {"status": "error", "message": "Missing key or value"}
        elif "get_preference" in task_name.lower():
            key = params.get("key")
            project_id = params.get("project_id", "default_project")
            if key:
                value = self.store.get_preference(project_id, key)
                return {"status": "success", "value": value}
            return {"status": "error", "message": "Missing key"}
            
        return {"status": "error", "message": f"Unknown memory task: {task_name}"}
