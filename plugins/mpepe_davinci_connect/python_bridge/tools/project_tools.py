"""project_tools — Project color science and timeline settings."""
import logging
from typing import Any, Optional
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.project")

def get_project_settings(setting_name: Optional[str] = None) -> Any:
    """Returns a project setting, or all settings if name is None."""
    _, project = get_current_project()
    if not project:
        return None
    if setting_name:
        if hasattr(project, "GetSetting"):
            return project.GetSetting(setting_name)
    else:
        if hasattr(project, "GetSetting"):
            return project.GetSetting()
    return None

def set_project_setting(setting_name: str, setting_value: Any) -> bool:
    """Sets a project-level setting (e.g. colorScienceMode, timelineColorSpaceName)."""
    _, project = get_current_project()
    if not project:
        return False
    if hasattr(project, "SetSetting"):
        return project.SetSetting(setting_name, str(setting_value))
    return False
