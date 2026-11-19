import sqlite3
import os
import json
import logging
from typing import Dict, Any, List

logger = logging.getLogger("cj_grader.ledger")

class GradeLedger:
    def __init__(self, db_path: str = "grade_ledger.db"):
        # We place the ledger db in a designated app data folder, or next to script for now
        self.db_path = db_path
        self._init_db()
        
    def _init_db(self):
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS actions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    timeline_id TEXT,
                    track_index INTEGER,
                    clip_index INTEGER,
                    node_index INTEGER,
                    action_type TEXT,
                    payload TEXT,
                    agent_id TEXT
                )
            """)
            conn.commit()
            
    def record_action(self, 
                     timeline_id: str, 
                     track_index: int, 
                     clip_index: int, 
                     node_index: int,
                     action_type: str, 
                     payload: Dict[str, Any],
                     agent_id: str):
        """Records an action in the ledger."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT INTO actions 
                    (timeline_id, track_index, clip_index, node_index, action_type, payload, agent_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (
                    timeline_id, 
                    track_index, 
                    clip_index, 
                    node_index, 
                    action_type, 
                    json.dumps(payload),
                    agent_id
                ))
                conn.commit()
            logger.info(f"Recorded action {action_type} from {agent_id}")
        except Exception as e:
            logger.error(f"Failed to record action in ledger: {e}")

    def get_clip_history(self, timeline_id: str, track_index: int, clip_index: int) -> List[Dict[str, Any]]:
        """Retrieves the history of actions for a specific clip."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT * FROM actions 
                    WHERE timeline_id = ? AND track_index = ? AND clip_index = ?
                    ORDER BY timestamp ASC
                """, (timeline_id, track_index, clip_index))
                
                rows = []
                for row in cursor.fetchall():
                    r_dict = dict(row)
                    r_dict['payload'] = json.loads(r_dict['payload'])
                    rows.append(r_dict)
                return rows
        except Exception as e:
            logger.error(f"Failed to get clip history: {e}")
            return []
