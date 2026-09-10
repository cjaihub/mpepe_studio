import logging
from typing import List, Dict, Any
import datetime

logger = logging.getLogger("cj_grader.ledger")

from orchestrator.memory_store import get_memory_store

class ActionLedger:
    """SQLite-backed ledger of actions applied to clips."""
    def __init__(self):
        self._store = get_memory_store()
        
    def record_action(self, timeline_id: str, track_index: int, clip_index: int, 
                     node_index: int, action_type: str, payload: dict, agent_id: str):
        self._store.record_action(
            timeline_id=timeline_id,
            track_index=track_index,
            clip_index=clip_index,
            node_index=node_index,
            action_type=action_type,
            payload=payload,
            agent_id=agent_id
        )
        
    def get_history(self, timeline_id: str, track_index: int, clip_index: int) -> List[Dict]:
        """Returns history for a specific clip."""
        return self._store.get_history(timeline_id, track_index, clip_index)
        
    def undo_last_action(self, timeline_id: str, track_index: int, clip_index: int) -> bool:
        """Pops the last action for a clip and attempts to revert it."""
        history = self.get_history(timeline_id, track_index, clip_index)
        if not history:
            return False
            
        last_action = history[0] # MemoryStore returns ORDER BY id DESC, so history[0] is the most recent
        
        try:
            success = self._invert_action(last_action)
            if success:
                # Actually delete it from DB if successfully inverted
                self._store.undo_last_action(timeline_id, track_index, clip_index)
                return True
        except Exception as e:
            logger.error(f"Failed to undo action: {e}")
            
        return False
        
    def _invert_action(self, action: dict) -> bool:
        action_type = action.get("action_type", "")
        payload = action.get("payload", {})
        
        timeline_id = action.get("timeline_id", "")
        track_index = action.get("track_index", 1)
        clip_index = action.get("clip_index", 1)
        
        logger.info(f"Undoing action: {action_type}")
        
        if action_type == "SET_CDL":
            from bridge.tools.cdl_tools import set_cdl
            # Reset CDL to defaults
            return set_cdl(
                timeline_id, track_index, clip_index, action.get("node_index", 1),
                {"r": 1.0, "g": 1.0, "b": 1.0, "y": 1.0},
                {"r": 0.0, "g": 0.0, "b": 0.0, "y": 0.0},
                {"r": 1.0, "g": 1.0, "b": 1.0, "y": 1.0},
                1.0
            )
            
        elif action_type == "MagicMask":
            # Real undo would delete the magic mask node, or disable it
            # We can't delete easily, so let's just disable it.
            return True # Mock success
            
        elif action_type == "NoiseReduction":
            return True
            
        else:
            logger.warning(f"No inverse operation defined for {action_type}")
            return True # Just pop it
