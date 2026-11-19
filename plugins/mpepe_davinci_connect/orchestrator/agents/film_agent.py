"""film_agent — film print emulation using the LUTs Resolve ships in its LUT folder."""
import logging

from bridge.tools.lut_tools import set_lut, search_luts, node_count
from .agent_base import AgentBase, step_target, ok, fail

logger = logging.getLogger("cj_grader.agents.film")

# Look name -> search words matched against Resolve's bundled "Film Looks" LUTs.
FILM_LOOKS = {
    "kodak_2383": "film looks rec709 kodak 2383 d65",
    "kodak_2393": "film looks rec709 kodak 2393 d65",
    "fuji_3513": "film looks rec709 fujifilm 3513",
    "fuji_3510": "film looks rec709 fujifilm 3513",
}


def resolve_film_lut(look: str) -> str:
    """Finds the installed LUT for a look; falls back to a plain keyword search."""
    query = FILM_LOOKS.get(look.lower(), look)
    for q in (query, look.replace("_", " ")):
        matches = search_luts(q, limit=1)
        if matches:
            return matches[0]["path"]
    return ""


class FilmAgent(AgentBase):
    name = "Film"

    def __init__(self, bridge_client=None):
        super().__init__(bridge_client=bridge_client)

    def execute_task(self, task: dict) -> dict:
        params = task.get("params", {}) or {}
        t = step_target(task)
        look = str(params.get("look", "kodak_2383"))
        logger.info(f"Film Agent: look '{look}'")

        lut_path = params.get("lut_path") or resolve_film_lut(look)
        if not lut_path:
            return fail(f"No installed film LUT matches '{look}'. Known looks: {', '.join(FILM_LOOKS)}.")

        # Film print goes last in the node tree unless a node was specified.
        node = int(params.get("node_index") or node_count(t["track_index"], t["clip_index"]) or t["node_index"])
        if set_lut(t["timeline_id"], t["track_index"], t["clip_index"], node, lut_path):
            return ok(f"Film look '{look}' applied on node {node} ({lut_path}).", lut=lut_path)
        return fail(f"Resolve could not apply {lut_path} to node {node}.")
