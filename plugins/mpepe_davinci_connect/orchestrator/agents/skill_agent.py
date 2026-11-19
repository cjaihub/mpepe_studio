"""skill_agent — applies saved Skills (reusable CDL looks) and learns new ones."""
import json
import logging

from orchestrator.memory_store import get_memory_store
from .agent_base import AgentBase, step_target, ok, fail
from .color_scientist import apply_cdl_to_target

logger = logging.getLogger("cj_grader.agents.skill_agent")


def find_skill(name: str):
    """Exact (case-insensitive) name match first, then substring match; newest wins."""
    skills = get_memory_store().list_skills()
    wanted = name.strip().lower()
    for s in skills:
        if s["name"].lower() == wanted:
            return s
    for s in skills:
        if wanted in s["name"].lower():
            return s
    return None


def _flatten(payload: dict) -> dict:
    """SET_CDL ledger payload -> flat Director-style CDL params."""
    flat = {"saturation": payload.get("saturation", 1.0)}
    for part in ("slope", "offset", "power"):
        for c in "rgb":
            flat[f"{part}_{c}"] = (payload.get(part) or {}).get(c, 0.0 if part == "offset" else 1.0)
    return flat


class SkillAgent(AgentBase):
    name = "Skill"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict):
        params = task.get("params", {}) or {}
        t = step_target(task)
        skill_name = params.get("skill_name", "")
        action = params.get("action") or ("learn" if "learn" in task.get("task", "").lower() else "apply")
        logger.info(f"Skill Agent: {action} '{skill_name}'")

        if not skill_name:
            return fail("No skill_name provided.")

        if action == "learn":
            # Resolve cannot read a node's CDL back, so learn from the last grade CJ applied.
            store = get_memory_store()
            cdl = params.get("cdl")
            if not cdl:
                history = [h for h in store.get_history(t["timeline_id"], t["track_index"], t["clip_index"])
                           if h.get("action_type") == "SET_CDL"]
                if not history:
                    return fail("No CJ grade recorded on this clip yet. Grade it first, then teach the skill.")
                cdl = _flatten(json.loads(history[0]["payload"]))
            skill_id = store.save_skill(name=skill_name, description=params.get("description", "Learned from clip grade"),
                                        tags=params.get("tags", []), cdl_json=json.dumps(cdl))
            return ok(f"Learned skill '{skill_name}' (id {skill_id}).")

        skill = find_skill(skill_name)
        if not skill:
            names = ", ".join(s["name"] for s in get_memory_store().list_skills()[:8]) or "none saved yet"
            return fail(f"No skill named '{skill_name}'. Available: {names}.")
        cdl = json.loads(skill["cdl_json"] or "{}")
        result = apply_cdl_to_target(t, cdl, "skill_agent",
                                     append_new_node=bool(params.get("append_new_node", True)))
        if result["status"] == "success":
            result["message"] = f"Applied skill '{skill['name']}'. " + result["message"]
        return result
