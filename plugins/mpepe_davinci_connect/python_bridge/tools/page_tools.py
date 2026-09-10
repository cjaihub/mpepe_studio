"""page_tools — DaVinci Resolve page navigation."""
import logging
from ..connection import get_current_project

logger = logging.getLogger("cj_grader.tools.page")

VALID_PAGES = {"media", "cut", "edit", "fusion", "color", "fairlight", "deliver"}

def open_page(page: str) -> bool:
    """Navigates Resolve to the specified page."""
    if page.lower() not in VALID_PAGES:
        logger.error(f"Invalid page name '{page}'. Must be one of: {VALID_PAGES}")
        return False
    _, project = get_current_project()
    if not project:
        return False
    # page navigation is on the Resolve object, not project
    from ..connection import get_resolve
    resolve = get_resolve()
    if resolve and hasattr(resolve, "OpenPage"):
        return resolve.OpenPage(page)
    return False
