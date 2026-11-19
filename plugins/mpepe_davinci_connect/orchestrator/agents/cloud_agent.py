"""cloud_agent — local backup of CJ Grader memory, plus consent-gated cloud sync."""
import datetime
import logging
import os
import shutil

from orchestrator.memory_store import get_memory_store
from .agent_base import AgentBase, ok, fail, skipped

logger = logging.getLogger("cj_grader.agents.cloud")


class CloudAgent(AgentBase):
    name = "Cloud"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def _backup(self) -> str:
        store = get_memory_store()
        backup_dir = os.path.join(os.path.dirname(store.db_path), "backups")
        os.makedirs(backup_dir, exist_ok=True)
        dest = os.path.join(backup_dir, f"memory_{datetime.datetime.now():%Y%m%d_%H%M%S}.db")
        store._conn.commit()
        shutil.copy2(store.db_path, dest)
        return dest

    def execute_task(self, task: dict) -> dict:
        task_name = task.get("task", "").lower()
        params = task.get("params", {}) or {}
        logger.info(f"Cloud Agent: {task_name}")

        if "backup" in task_name:
            try:
                return ok(f"Backed up grades, skills and preferences to {self._backup()}.")
            except Exception as e:
                return fail(f"Backup failed: {e}")

        if "sync" in task_name or "upload" in task_name:
            # Nothing leaves this machine without an explicit yes from the user.
            if not params.get("consent"):
                return skipped("Cloud sync needs your consent; confirm the upload to continue.")
            user_id, username = params.get("user_id"), params.get("username", "")
            if not user_id:
                return fail("Cloud sync needs a signed-in user_id.")
            try:
                from orchestrator import database
                prefs = get_memory_store().get_all_preferences(params.get("project_id", "default_project"))
                if not database.sync_to_cloud(user_id, username, prefs):
                    return fail("Cloud sync is not configured (no Firebase service account on this machine).")
                return ok(f"Synced {len(prefs)} preference(s) to the cloud.")
            except Exception as e:
                return fail(f"Cloud sync failed: {e}")

        return fail(f"Unknown task for Cloud: {task.get('task', '')}")
