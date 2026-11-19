"""color_scientist — CDL grading and LUT application on a clip node."""
import json
import logging

from bridge.tools.cdl_tools import set_cdl
from bridge.tools.lut_tools import set_lut, search_luts
from .agent_base import AgentBase, step_target, ok, fail

logger = logging.getLogger("cj_grader.agents.color_scientist")

_CDL_KEYS = ("slope", "offset", "power", "saturation")


def cdl_from_params(params: dict):
    """Unpacks the Director's flat CDL params into Resolve's slope/offset/power dicts."""
    slope = {c: float(params.get(f"slope_{c}", 1.0)) for c in "rgb"}
    offset = {c: float(params.get(f"offset_{c}", 0.0)) for c in "rgb"}
    power = {c: float(params.get(f"power_{c}", 1.0)) for c in "rgb"}
    slope["y"], offset["y"], power["y"] = 1.0, 0.0, 1.0
    return slope, offset, power, float(params.get("saturation", 1.0))


def record_cdl(target: dict, slope, offset, power, saturation, snapshot: str, agent_id: str):
    """Writes the applied grade to the action ledger so it can be undone or learned as a skill."""
    try:
        from orchestrator.memory_store import get_memory_store
        get_memory_store().record_action(
            timeline_id=target["timeline_id"], track_index=target["track_index"],
            clip_index=target["clip_index"], node_index=target["node_index"],
            action_type="SET_CDL",
            payload={"slope": slope, "offset": offset, "power": power,
                     "saturation": saturation, "snapshot": snapshot},
            agent_id=agent_id, snapshot=snapshot,
        )
    except Exception as e:
        logger.warning(f"Could not record CDL in ledger: {e}")


def apply_cdl_to_target(target: dict, params: dict, agent_id: str, append_new_node: bool = False) -> dict:
    slope, offset, power, saturation = cdl_from_params(params)
    result = set_cdl(
        timeline_id=target["timeline_id"], track_index=target["track_index"],
        clip_index=target["clip_index"], node_index=target["node_index"],
        slope=slope, offset=offset, power=power, saturation=saturation,
        append_new_node=append_new_node,
    )
    success = bool(result.get("success")) if isinstance(result, dict) else bool(result)
    snapshot = result.get("snapshot", "") if isinstance(result, dict) else ""
    grade_json = json.dumps({
        "slope": (slope["r"], slope["g"], slope["b"]),
        "offset": (offset["r"], offset["g"], offset["b"]),
        "power": (power["r"], power["g"], power["b"]),
        "saturation": saturation,
    })
    if not success:
        return fail("Resolve rejected the CDL (is a project open with a clip at that position?)",
                    detail=f"[GRADE_PARAMS] {grade_json}")
    record_cdl(target, slope, offset, power, saturation, snapshot, agent_id)
    note = f" (snapshot {snapshot})" if snapshot else ""
    return ok(f"Applied CDL to clip {target['clip_index']}{note}",
              detail=f"[GRADE_PARAMS] {grade_json}", snapshot=snapshot)


class ColorScientist(AgentBase):
    """Handles CDLs, LUTs, and general color manipulation."""
    name = "Color Scientist"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict):
        task_desc = task.get("task", "")
        params = task.get("params", {}) or {}
        target = step_target(task)
        logger.info(f"Color Scientist: {task_desc}")

        has_cdl = any(k.startswith(_CDL_KEYS) for k in params)
        wants_lut = "lut" in task_desc.lower() or params.get("lut_path") or params.get("lut")

        if has_cdl or "cdl" in task_desc.lower():
            try:
                from bridge.tools.color_management_tools import get_color_science
                cs = get_color_science()
                logger.info(f"Color science: {cs.get('color_science_mode')} / {cs.get('timeline_color_space')}")
            except Exception as e:
                logger.debug(f"Color science read failed: {e}")
            return apply_cdl_to_target(target, params, "color_scientist",
                                       append_new_node=bool(params.get("append_new_node", False)))

        if wants_lut:
            lut_path = params.get("lut_path", "")
            if not lut_path and params.get("lut"):
                matches = search_luts(str(params["lut"]), limit=1)
                lut_path = matches[0]["path"] if matches else ""
            if not lut_path:
                return fail("No LUT path given and no installed LUT matched.")
            if set_lut(target["timeline_id"], target["track_index"], target["clip_index"],
                       target["node_index"], lut_path):
                return ok(f"Applied LUT {lut_path} to node {target['node_index']}")
            return fail(f"Resolve could not apply LUT {lut_path}")

        return fail("Color Scientist needs CDL params (slope_*/offset_*/power_*/saturation) or a LUT.")
