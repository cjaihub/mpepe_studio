import logging
from typing import Dict, Any, Tuple

logger = logging.getLogger("cj_grader.capability")

# Based on known gates from Resolve Scripting API reference
VERSION_GATES = [
    {
        "symbol": "Resolve.GetFairlightPresets",
        "introduced_in": "20.2.2"
    },
    {
        "symbol": "Timeline.GetSelectedClips",
        "introduced_in": "21.0.4"
    },
    {
        "symbol": "Project.SetRenderSettings DataBurnIn",
        "introduced_in": "21.0.4"
    }
]

class CapabilityProbe:
    def __init__(self, resolve: Any):
        self.resolve = resolve
        self._version = self._parse_version(resolve.GetVersionString())
        self._is_studio = "Studio" in resolve.GetProductName()
        
    def _parse_version(self, version_str: str) -> Tuple[int, ...]:
        try:
            parts = [int(p) for p in version_str.split(".") if p.isdigit()]
            return tuple(parts)
        except Exception:
            return (0,)
            
    def _at_least(self, required: str) -> bool:
        try:
            req_parts = tuple(int(p) for p in required.split(".") if p.isdigit())
            width = max(len(self._version), len(req_parts))
            pa = self._version + (0,) * (width - len(self._version))
            pb = req_parts + (0,) * (width - len(req_parts))
            return pa >= pb
        except Exception:
            return False
            
    def get_capabilities(self) -> Dict[str, Any]:
        """Returns a matrix of available capabilities."""
        caps = {
            "version": ".".join(map(str, self._version)),
            "is_studio": self._is_studio,
            "neural_engine": self._is_studio, # Most AI tools require Studio
            "features": {
                "magic_mask": {
                    "available": self._is_studio,
                    "mode": "guided" if not self._at_least("21.0.0") else "automated"
                },
                "face_refinement": {
                    "available": self._is_studio,
                    "mode": "guided"
                },
                "smart_reframe": {
                    "available": self._is_studio,
                    "mode": "automated"
                },
                "stabilize": {
                    "available": True,
                    "mode": "automated"
                }
            },
            "gates": {}
        }
        
        for gate in VERSION_GATES:
            caps["gates"][gate["symbol"]] = self._at_least(gate["introduced_in"])
            
        return caps
        
    def require_studio(self, feature_name: str) -> bool:
        """Checks if the feature is allowed on the current Resolve edition."""
        if not self._is_studio:
            logger.warning(f"Feature '{feature_name}' requires DaVinci Resolve Studio.")
            return False
        return True
