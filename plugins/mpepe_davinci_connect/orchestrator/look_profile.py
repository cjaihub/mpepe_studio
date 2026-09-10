from dataclasses import dataclass, field
from typing import Dict, List, Optional
import json

@dataclass
class LookProfile:
    """
    A LookProfile represents a set of color grading parameters derived from 
    a reference image, textual description, or historical grade. It serves
    as the 'memory' for a specific cinematic look.
    """
    id: str
    name: str
    description: str
    
    # The CDL parameters that represent this look
    cdl_params: Dict[str, float] = field(default_factory=lambda: {
        "slope_r": 1.0, "slope_g": 1.0, "slope_b": 1.0,
        "offset_r": 0.0, "offset_g": 0.0, "offset_b": 0.0,
        "power_r": 1.0, "power_g": 1.0, "power_b": 1.0,
        "saturation": 1.0
    })
    
    # Tags to help categorize the look (e.g. "warm", "cinematic", "high-contrast")
    tags: List[str] = field(default_factory=list)
    
    # Optional path or URL to the reference image used to generate this look
    reference_image_uri: Optional[str] = None
    
    def to_json(self) -> str:
        return json.dumps({
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "cdl_params": self.cdl_params,
            "tags": self.tags,
            "reference_image_uri": self.reference_image_uri
        })
        
    @classmethod
    def from_json(cls, json_str: str) -> 'LookProfile':
        data = json.loads(json_str)
        return cls(
            id=data.get("id", ""),
            name=data.get("name", ""),
            description=data.get("description", ""),
            cdl_params=data.get("cdl_params", {}),
            tags=data.get("tags", []),
            reference_image_uri=data.get("reference_image_uri")
        )
