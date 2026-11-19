"""lut_agent — searches Resolve's LUT folder and optionally applies the best match."""
import json
import logging

from bridge.tools import lut_tools
from .agent_base import AgentBase, ok, fail

logger = logging.getLogger("cj_grader.agents.lut")


class LutAgent(AgentBase):
    def __init__(self):
        super().__init__(name="LUT", description="Searches for LUTs and applies them.")

    @property
    def lut_dir(self) -> str:
        return lut_tools.lut_root()

    def execute(self, prompt: str, timeline_id: str = None, **kwargs) -> dict:
        keyword = str(kwargs.get("keyword") or kwargs.get("lut") or prompt or "").strip()
        apply = bool(kwargs.get("apply", "apply" in (prompt or "").lower()))
        self.emit_progress(1, 3, f"Searching LUTs for '{keyword}'...")

        if not keyword:
            return fail("Tell me which LUT to look for (keyword).")
        matches = lut_tools.search_luts(keyword, limit=10)
        if not matches:
            # retry with the most specific single word, e.g. "apply the 2383 lut" -> "2383"
            words = [w for w in keyword.lower().split() if w not in ("apply", "the", "lut", "a", "use", "find")]
            for w in sorted(words, key=len, reverse=True):
                matches = lut_tools.search_luts(w, limit=10)
                if matches:
                    break
        detail = f"[LUT_RESULTS] {json.dumps({'luts': matches})}"
        if not matches:
            return ok(f"No LUTs in {self.lut_dir} match '{keyword}'.", detail=detail)

        if not apply:
            return ok(f"Found {len(matches)} LUT(s) matching '{keyword}'.", detail=detail)

        best = matches[0]["path"]
        self.emit_progress(2, 3, f"Applying {best}...")
        node = int(kwargs.get("node_index", 1))
        if lut_tools.set_lut(timeline_id or "", int(kwargs.get("track_index", 1)),
                             int(kwargs.get("clip_index", 1)), node, best):
            return ok(f"Applied {best} on node {node}.", detail=detail)
        return fail(f"Found {best} but Resolve could not apply it.", detail=detail)
