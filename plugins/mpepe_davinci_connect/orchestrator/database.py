import sqlite3
import json
import logging
import os
try:  # cloud sync is optional; the local database works without firebase-admin
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    firebase_admin = None

DB_PATH = os.path.join(os.path.dirname(__file__), 'studio_data.db')
logger = logging.getLogger(__name__)

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Users table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        preferences TEXT
    )
    ''')
    
    # Projects table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        project_name TEXT,
        category TEXT,
        settings TEXT,
        FOREIGN KEY (user_id) REFERENCES users(id)
    )
    ''')
    
    conn.commit()
    conn.close()

def register_user(username, password):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("INSERT INTO users (username, password, preferences) VALUES (?, ?, ?)", 
                       (username, password, json.dumps({})))
        conn.commit()
        return True, "User registered successfully."
    except sqlite3.IntegrityError:
        return False, "Username already exists."
    finally:
        conn.close()

def login_user(username, password):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT id, preferences FROM users WHERE username = ? AND password = ?", (username, password))
    user = cursor.fetchone()
    conn.close()
    
    if user:
        return True, {"user_id": user[0], "username": username, "preferences": json.loads(user[1])}
    return False, "Invalid credentials."

def create_project(user_id, project_name, category, settings=None):
    if settings is None:
        settings = {}
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO projects (user_id, project_name, category, settings) VALUES (?, ?, ?, ?)",
                   (user_id, project_name, category, json.dumps(settings)))
    project_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return project_id

# Firebase Global Client
_firebase_db = None

def _init_firebase():
    global _firebase_db
    if firebase_admin is None:
        logger.warning("firebase-admin not installed. Cloud sync disabled.")
        return
    try:
        if not firebase_admin._apps:
            # Expects a serviceAccountKey.json in the data folder for prod
            cred_path = os.path.join(os.path.dirname(DB_PATH), 'serviceAccountKey.json')
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                _firebase_db = firestore.client()
                logger.info("Firebase initialized.")
            else:
                _firebase_db = None
                logger.warning("No serviceAccountKey.json found. Cloud sync disabled.")
    except Exception as e:
        logger.error(f"Failed to init Firebase: {e}")
        _firebase_db = None

def sync_to_cloud(user_id: int, username: str, preferences: dict) -> bool:
    global _firebase_db
    if _firebase_db is None:
        _init_firebase()
    if _firebase_db is None:
        return False

    try:
        _firebase_db.collection('users').document(str(user_id)).set({
            'username': username,
            'preferences': preferences
        }, merge=True)
        logger.info(f"Synced user {user_id} to Firebase.")
        return True
    except Exception as e:
        logger.error(f"Cloud sync failed: {e}")
        return False

def pull_from_cloud(user_id: int):
    global _firebase_db
    if _firebase_db is None:
        _init_firebase()
    if _firebase_db is None: return None
    
    try:
        doc = _firebase_db.collection('users').document(str(user_id)).get()
        if doc.exists:
            data = doc.to_dict()
            logger.info(f"Pulled user {user_id} from Firebase.")
            return data
    except Exception as e:
        logger.error(f"Cloud pull failed: {e}")
    return None

# Initialize the database on module import
init_db()
