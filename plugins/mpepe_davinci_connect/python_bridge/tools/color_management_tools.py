"""color_management_tools — Reads project color science settings before grading operations."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.color_mgmt")

# Known Resolve color science modes
COLOR_SCIENCE_MODES = {
    "davinciYRGB": "DaVinci YRGB",
    "davinciYRGBColorManagedV2": "DaVinci YRGB Color Managed",
    "ACEScc": "ACEScc",
    "ACEScct": "ACEScct",
}


def get_color_science() -> dict:
    """
    Reads the project's color science configuration.
    Returns color science mode, working color space, timeline/output spaces.
    This must be called before any CDL/LUT operation so the AI can generate
    color-space-aware corrections.
    """
    _, project = get_current_project()
    if not project:
        return {"error": "No active project", "mode": "unknown"}

    settings = {}

    # Core color science mode
    mode = project.GetSetting("colorScienceMode") or "unknown"
    settings["color_science_mode"] = COLOR_SCIENCE_MODES.get(mode, mode)
    settings["color_science_mode_raw"] = mode

    # Working color space (DaVinci Wide Gamut, Rec.709, ACEScct, etc.)
    settings["timeline_color_space"] = project.GetSetting("colorSpaceTimeline") or "Rec.709"
    settings["output_color_space"] = project.GetSetting("colorSpaceOutput") or "Rec.709"

    # Input color space (if set project-wide)
    settings["input_color_space"] = project.GetSetting("colorSpaceInput") or "Project"

    # Gamma settings
    settings["timeline_gamma"] = project.GetSetting("timelineGamma") or ""
    settings["output_gamma"] = project.GetSetting("outputGamma") or ""

    # ACES-specific settings (only meaningful in ACES mode)
    if "ACES" in mode:
        settings["aces_version"] = project.GetSetting("ACESVersion") or ""
        settings["aces_input_transform"] = project.GetSetting("ACESInputTransform") or ""
        settings["aces_output_transform"] = project.GetSetting("ACESOutputTransform") or ""

    # HDR metadata
    settings["hdr_mastering_is_on"] = project.GetSetting("hdrMasteringIsOn") or "0"
    settings["hdr_mastering_luminance_max"] = project.GetSetting("hdrMasteringLuminanceMax") or ""

    logger.info(f"Color science: {settings['color_science_mode']} | "
                f"Timeline: {settings['timeline_color_space']} | "
                f"Output: {settings['output_color_space']}")

    return settings


def get_working_color_space() -> str:
    """Convenience method — returns just the timeline working color space string."""
    cs = get_color_science()
    return cs.get("timeline_color_space", "Rec.709")


def is_color_managed() -> bool:
    """Returns True if the project uses DaVinci Color Managed or ACES workflow."""
    cs = get_color_science()
    mode = cs.get("color_science_mode_raw", "")
    return "ColorManaged" in mode or "ACES" in mode
