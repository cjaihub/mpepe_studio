import logging
from typing import Optional, Any, Tuple
from .resolve_env import setup_resolve_env

logger = logging.getLogger("cj_grader.connection")

class ResolveConnection:
    _instance = None
    _resolve = None
    
    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def connect(self) -> Optional[Any]:
        """Initialize connection to DaVinci Resolve application."""
        if self._resolve is not None:
            return self._resolve
            
        try:
            setup_resolve_env()
            import DaVinciResolveScript as dvr_script
            
            # Use local scripting by default for Studio
            self._resolve = dvr_script.scriptapp("Resolve")
            
            if self._resolve is None:
                logger.error("Failed to get Resolve object. Is DaVinci Resolve Studio running?")
                return None
                
            logger.info(f"Connected to DaVinci Resolve: {self._resolve.GetProductName()} {self._resolve.GetVersionString()}")
            return self._resolve
            
        except ImportError as e:
            logger.error("Failed to import DaVinciResolveScript. Make sure environment variables are set correctly.")
            logger.error(str(e))
            return None
        except Exception as e:
            logger.error(f"Unexpected error initializing Resolve: {str(e)}")
            return None

def get_resolve() -> Optional[Any]:
    return ResolveConnection.get_instance().connect()

def get_project_manager() -> Optional[Any]:
    resolve = get_resolve()
    if resolve:
        return resolve.GetProjectManager()
    return None

def get_current_project() -> Tuple[Optional[Any], Optional[Any]]:
    pm = get_project_manager()
    if pm:
        return pm, pm.GetCurrentProject()
    return None, None
