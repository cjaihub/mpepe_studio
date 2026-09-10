"""memory_store — SQLite-backed persistent store for grades, preferences, and look profiles."""
import sqlite3
import json
import os
import logging
import datetime
from typing import List, Dict, Any, Optional

logger = logging.getLogger("cj_grader.memory_store")

DEFAULT_DB_PATH = os.path.join(os.path.expanduser("~"), ".cj_grader", "memory.db")


class MemoryStore:
    """Thread-safe SQLite store for per-project grade history, preferences, and look profiles."""

    def __init__(self, db_path: str = DEFAULT_DB_PATH):
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        self.db_path = db_path
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._migrate()
        logger.info(f"MemoryStore initialized at {db_path}")

    def _migrate(self):
        """Create tables if they don't exist."""
        cur = self._conn.cursor()

        cur.execute("""
            CREATE TABLE IF NOT EXISTS grade_history (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp   TEXT NOT NULL,
                project_id  TEXT NOT NULL DEFAULT '',
                timeline_id TEXT NOT NULL DEFAULT '',
                track_index INTEGER NOT NULL DEFAULT 1,
                clip_index  INTEGER NOT NULL DEFAULT 1,
                node_index  INTEGER NOT NULL DEFAULT 1,
                action_type TEXT NOT NULL,
                payload     TEXT NOT NULL DEFAULT '{}',
                agent_id    TEXT NOT NULL DEFAULT '',
                snapshot    TEXT NOT NULL DEFAULT ''
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS preferences (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id  TEXT NOT NULL,
                key         TEXT NOT NULL,
                value       TEXT NOT NULL,
                updated_at  TEXT NOT NULL,
                UNIQUE(project_id, key)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS look_profiles (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id   TEXT NOT NULL DEFAULT '',
                name         TEXT NOT NULL,
                slope_r      REAL NOT NULL DEFAULT 1.0,
                slope_g      REAL NOT NULL DEFAULT 1.0,
                slope_b      REAL NOT NULL DEFAULT 1.0,
                offset_r     REAL NOT NULL DEFAULT 0.0,
                offset_g     REAL NOT NULL DEFAULT 0.0,
                offset_b     REAL NOT NULL DEFAULT 0.0,
                power_r      REAL NOT NULL DEFAULT 1.0,
                power_g      REAL NOT NULL DEFAULT 1.0,
                power_b      REAL NOT NULL DEFAULT 1.0,
                saturation   REAL NOT NULL DEFAULT 1.0,
                mood_tags    TEXT NOT NULL DEFAULT '[]',
                source_hash  TEXT NOT NULL DEFAULT '',
                lut_path     TEXT NOT NULL DEFAULT '',
                created_at   TEXT NOT NULL
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS skills (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id   TEXT NOT NULL DEFAULT '',
                name         TEXT NOT NULL,
                description  TEXT NOT NULL DEFAULT '',
                tags         TEXT NOT NULL DEFAULT '[]',
                cdl_json     TEXT NOT NULL DEFAULT '{}',
                thumbnail_b64 TEXT NOT NULL DEFAULT '',
                source_image_path TEXT NOT NULL DEFAULT '',
                created_at   TEXT NOT NULL
            )
        """)

        self._conn.commit()

    # ── Grade History ─────────────────────────────────────────────────────

    def record_action(self, timeline_id: str, track_index: int, clip_index: int,
                      node_index: int, action_type: str, payload: dict,
                      agent_id: str, project_id: str = "", snapshot: str = ""):
        cur = self._conn.cursor()
        cur.execute("""
            INSERT INTO grade_history
                (timestamp, project_id, timeline_id, track_index, clip_index, node_index,
                 action_type, payload, agent_id, snapshot)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            datetime.datetime.now().isoformat(),
            project_id, timeline_id, track_index, clip_index, node_index,
            action_type, json.dumps(payload), agent_id, snapshot,
        ))
        self._conn.commit()
        logger.info(f"Recorded: {action_type} by {agent_id}")

    def get_history(self, timeline_id: str, track_index: int, clip_index: int,
                    limit: int = 50) -> List[Dict[str, Any]]:
        cur = self._conn.cursor()
        cur.execute("""
            SELECT * FROM grade_history
            WHERE timeline_id = ? AND track_index = ? AND clip_index = ?
            ORDER BY id DESC LIMIT ?
        """, (timeline_id, track_index, clip_index, limit))
        rows = cur.fetchall()
        return [dict(r) for r in rows]

    def get_full_history(self, project_id: str = "", limit: int = 200) -> List[Dict[str, Any]]:
        cur = self._conn.cursor()
        if project_id:
            cur.execute("SELECT * FROM grade_history WHERE project_id = ? ORDER BY id DESC LIMIT ?",
                        (project_id, limit))
        else:
            cur.execute("SELECT * FROM grade_history ORDER BY id DESC LIMIT ?", (limit,))
        return [dict(r) for r in cur.fetchall()]

    def undo_last_action(self, timeline_id: str, track_index: int, clip_index: int) -> Optional[Dict]:
        history = self.get_history(timeline_id, track_index, clip_index, limit=1)
        if not history:
            return None
        last = history[0]
        cur = self._conn.cursor()
        cur.execute("DELETE FROM grade_history WHERE id = ?", (last["id"],))
        self._conn.commit()
        return last

    # ── Preferences ───────────────────────────────────────────────────────

    def save_preference(self, project_id: str, key: str, value: Any):
        cur = self._conn.cursor()
        cur.execute("""
            INSERT INTO preferences (project_id, key, value, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(project_id, key) DO UPDATE SET value = ?, updated_at = ?
        """, (
            project_id, key, json.dumps(value), datetime.datetime.now().isoformat(),
            json.dumps(value), datetime.datetime.now().isoformat(),
        ))
        self._conn.commit()

    def get_preference(self, project_id: str, key: str, default: Any = None) -> Any:
        cur = self._conn.cursor()
        cur.execute("SELECT value FROM preferences WHERE project_id = ? AND key = ?",
                    (project_id, key))
        row = cur.fetchone()
        if row:
            try:
                return json.loads(row["value"])
            except json.JSONDecodeError:
                return row["value"]
        return default

    def get_all_preferences(self, project_id: str) -> Dict[str, Any]:
        cur = self._conn.cursor()
        cur.execute("SELECT key, value FROM preferences WHERE project_id = ?", (project_id,))
        result = {}
        for row in cur.fetchall():
            try:
                result[row["key"]] = json.loads(row["value"])
            except json.JSONDecodeError:
                result[row["key"]] = row["value"]
        return result

    # ── Look Profiles ─────────────────────────────────────────────────────

    def save_look_profile(self, name: str, slope: dict, offset: dict, power: dict,
                          saturation: float, mood_tags: list = None,
                          source_hash: str = "", lut_path: str = "",
                          project_id: str = "") -> int:
        cur = self._conn.cursor()
        cur.execute("""
            INSERT INTO look_profiles
                (project_id, name, slope_r, slope_g, slope_b,
                 offset_r, offset_g, offset_b,
                 power_r, power_g, power_b,
                 saturation, mood_tags, source_hash, lut_path, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            project_id, name,
            slope.get("r", 1.0), slope.get("g", 1.0), slope.get("b", 1.0),
            offset.get("r", 0.0), offset.get("g", 0.0), offset.get("b", 0.0),
            power.get("r", 1.0), power.get("g", 1.0), power.get("b", 1.0),
            saturation, json.dumps(mood_tags or []),
            source_hash, lut_path, datetime.datetime.now().isoformat(),
        ))
        self._conn.commit()
        return cur.lastrowid

    def list_look_profiles(self, project_id: str = "") -> List[Dict[str, Any]]:
        cur = self._conn.cursor()
        if project_id:
            cur.execute("SELECT * FROM look_profiles WHERE project_id = ? OR project_id = '' ORDER BY id DESC",
                        (project_id,))
        else:
            cur.execute("SELECT * FROM look_profiles ORDER BY id DESC")
        return [dict(r) for r in cur.fetchall()]

    def get_look_profile(self, profile_id: int) -> Optional[Dict[str, Any]]:
        cur = self._conn.cursor()
        cur.execute("SELECT * FROM look_profiles WHERE id = ?", (profile_id,))
        row = cur.fetchone()
        return dict(row) if row else None

    def delete_look_profile(self, profile_id: int) -> bool:
        cur = self._conn.cursor()
        cur.execute("DELETE FROM look_profiles WHERE id = ?", (profile_id,))
        self._conn.commit()
        return cur.rowcount > 0

    # ── Skills ────────────────────────────────────────────────────────────

    def save_skill(self, name: str, description: str, tags: list, cdl_json: str,
                   thumbnail_b64: str = "", source_image_path: str = "",
                   project_id: str = "") -> int:
        cur = self._conn.cursor()
        cur.execute("""
            INSERT INTO skills
                (project_id, name, description, tags, cdl_json,
                 thumbnail_b64, source_image_path, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            project_id, name, description, json.dumps(tags or []), cdl_json,
            thumbnail_b64, source_image_path, datetime.datetime.now().isoformat(),
        ))
        self._conn.commit()
        return cur.lastrowid

    def list_skills(self, project_id: str = "") -> List[Dict[str, Any]]:
        cur = self._conn.cursor()
        if project_id:
            cur.execute("SELECT * FROM skills WHERE project_id = ? OR project_id = '' ORDER BY id DESC",
                        (project_id,))
        else:
            cur.execute("SELECT * FROM skills ORDER BY id DESC")
        return [dict(r) for r in cur.fetchall()]

    def get_skill(self, skill_id: int) -> Optional[Dict[str, Any]]:
        cur = self._conn.cursor()
        cur.execute("SELECT * FROM skills WHERE id = ?", (skill_id,))
        row = cur.fetchone()
        return dict(row) if row else None

    def delete_skill(self, skill_id: int) -> bool:
        cur = self._conn.cursor()
        cur.execute("DELETE FROM skills WHERE id = ?", (skill_id,))
        self._conn.commit()
        return cur.rowcount > 0

    # ── Lifecycle ─────────────────────────────────────────────────────────


    def close(self):
        self._conn.close()


# Singleton accessor
_instance: Optional[MemoryStore] = None


def get_memory_store(db_path: str = DEFAULT_DB_PATH) -> MemoryStore:
    global _instance
    if _instance is None:
        _instance = MemoryStore(db_path)
    return _instance
