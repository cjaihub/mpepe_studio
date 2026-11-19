"""auditor_agent — scans every clip on a track for exposure and white balance problems.

For each clip it grabs the mid-clip frame from Resolve (raw 8-bit RGB thumbnail) and
measures it directly: crushed blacks, clipped highlights, overall exposure and colour
cast. No model call and no randomness, so the same timeline always audits the same way.
"""
import base64
import json
import logging
from typing import Any, Dict, List, Optional

from bridge.tools.thumbnail_tools import grab_clip_frame
from bridge.tools.timeline_tools import get_all_clips
from .agent_base import AgentBase, ok, fail

logger = logging.getLogger("cj_grader.agents.auditor")

CRUSH_LEVEL, CLIP_LEVEL = 4, 251          # 8-bit code values
CRUSH_RATIO, CLIP_RATIO = 0.08, 0.05      # share of pixels that triggers a flag
DARK_MEAN, BRIGHT_MEAN = 45, 200          # mean luma bounds
CAST_DELTA = 18                           # channel-mean spread that reads as a cast


def frame_stats(thumb: Dict[str, Any]) -> Optional[Dict[str, float]]:
    """Luma/colour statistics for a Resolve thumbnail dict, or None if it can't be read."""
    try:
        raw = base64.b64decode(thumb["data"])
        width, height = int(thumb["width"]), int(thumb["height"])
    except Exception:
        return None
    n = width * height
    if n <= 0 or len(raw) < n * 3:
        return None
    step = max(1, n // 20000)  # sample ~20k pixels, plenty for these measures
    count = crushed = clipped = 0
    sum_r = sum_g = sum_b = sum_y = 0
    for i in range(0, n, step):
        r, g, b = raw[3 * i], raw[3 * i + 1], raw[3 * i + 2]
        y = (54 * r + 183 * g + 19 * b) >> 8  # Rec.709 luma
        sum_r += r; sum_g += g; sum_b += b; sum_y += y
        crushed += y <= CRUSH_LEVEL
        clipped += y >= CLIP_LEVEL
        count += 1
    return {"mean_luma": sum_y / count, "crushed": crushed / count, "clipped": clipped / count,
            "mean_r": sum_r / count, "mean_g": sum_g / count, "mean_b": sum_b / count}


def issues_for(stats: Dict[str, float]) -> List[Dict[str, str]]:
    found = []
    if stats["crushed"] >= CRUSH_RATIO:
        found.append({"issue_type": "Exposure", "severity": "High",
                      "message": f"Shadows crushed ({stats['crushed']:.0%} of frame at black)."})
    if stats["clipped"] >= CLIP_RATIO:
        found.append({"issue_type": "Exposure", "severity": "High",
                      "message": f"Highlights clipped ({stats['clipped']:.0%} of frame at white)."})
    if stats["mean_luma"] < DARK_MEAN:
        found.append({"issue_type": "Exposure", "severity": "Medium", "message": "Frame is underexposed."})
    elif stats["mean_luma"] > BRIGHT_MEAN:
        found.append({"issue_type": "Exposure", "severity": "Medium", "message": "Frame is overexposed."})
    r, g, b = stats["mean_r"], stats["mean_g"], stats["mean_b"]
    if max(r, g, b) - min(r, g, b) >= CAST_DELTA:
        if g < min(r, b) and abs(r - b) < CAST_DELTA:
            cast = "magenta"
        elif g > max(r, b):
            cast = "green"
        elif r > b:
            cast = "warm/orange"
        else:
            cast = "cool/blue"
        found.append({"issue_type": "White Balance", "severity": "Medium",
                      "message": f"Image leans {cast} (R {r:.0f} / G {g:.0f} / B {b:.0f})."})
    return found


class AuditorAgent(AgentBase):
    def __init__(self):
        super().__init__(
            name="Auditor",
            description="Scans the timeline and audits clips for exposure and white balance issues.",
        )

    def execute(self, prompt: str, timeline_id: str = None, **kwargs) -> dict:
        track = int(kwargs.get("track_index", 1))
        self.emit_progress(1, 3, "Reading the timeline...")
        clips = get_all_clips(timeline_id or "", track)
        if not clips:
            return fail("No clips found. Is a timeline open in DaVinci Resolve?")

        self.emit_progress(2, 3, f"Scanning {len(clips)} clips for exposure and colour balance...")
        flagged, unread = [], 0
        for clip in clips:
            thumb = grab_clip_frame(track, clip["clip_index"])
            stats = frame_stats(thumb) if thumb else None
            if not stats:
                unread += 1
                continue
            for issue in issues_for(stats):
                flagged.append({"clip_index": clip["clip_index"], "clip_name": clip.get("name", ""), **issue})

        scanned = len(clips) - unread
        if scanned == 0:
            return fail("Resolve returned no frames to analyze (open the Color page and try again).")
        detail = f"[AUDIT_RESULTS] {json.dumps({'flagged_clips': flagged, 'scanned': scanned})}"
        bad = len({f['clip_index'] for f in flagged})
        summary = (f"All {scanned} clips passed the audit." if not flagged
                   else f"Found issues in {bad} of {scanned} clips.")
        if unread:
            summary += f" {unread} clip(s) could not be read."
        return ok(summary, detail=detail, flagged_clips=flagged)
