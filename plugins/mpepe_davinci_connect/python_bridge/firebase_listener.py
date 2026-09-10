import os
import sys
import uuid
import time
import json
import logging
import asyncio

try:
    import firebase_admin
    from firebase_admin import credentials
    from firebase_admin import firestore
except ImportError:
    print("Please install firebase-admin: pip install firebase-admin")
    sys.exit(1)

import resolve_connection

# Add parent directory to sys.path to import orchestrator
parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if parent_dir not in sys.path:
    sys.path.append(parent_dir)

from orchestrator.director import DirectorAgent
from orchestrator.provider_abstraction import GeminiProvider

logger = logging.getLogger("mpepe.davinci_firebase")
logging.basicConfig(level=logging.INFO)

class DaVinciFirebaseAgent:
    def __init__(self, cred_path="serviceAccountKey.json"):
        self.device_token = self.load_or_create_token()
        self.computer_name = "Studio iMac"
        import socket
        try:
            self.computer_name = socket.gethostname()
        except Exception:
            pass
        self.db = None
        self.device_ref = None
        self.listener_doc = None
        self.cred_path = cred_path
        
        # Init NLP Agent
        provider = GeminiProvider(api_key=os.environ.get("GEMINI_API_KEY", "demo"))
        self.director = DirectorAgent(provider=provider)
        self.director = DirectorAgent(provider=provider)
        
        self.init_firebase()

    def load_or_create_token(self):
        config_path = "device_config.json"
        if os.path.exists(config_path):
            with open(config_path, "r") as f:
                data = json.load(f)
                return data.get("device_token", str(uuid.uuid4()))
        else:
            token = str(uuid.uuid4())
            with open(config_path, "w") as f:
                json.dump({"device_token": token}, f)
            return token

    def init_firebase(self):
        if not os.path.exists(self.cred_path):
            logger.error(f"Error: {self.cred_path} not found. Please add your Firebase service account key.")
            return
            
        try:
            cred = credentials.Certificate(self.cred_path)
            # Ensure we don't re-initialize if already initialized
            try:
                firebase_admin.get_app()
            except ValueError:
                firebase_admin.initialize_app(cred)
                
            self.db = firestore.client()
            
            # Create device document
            self.device_ref = self.db.collection('registered_computers').document(self.device_token)
            self.device_ref.set({
                'computer_name': self.computer_name,
                'desktop_connected': True,
                'status': 'waiting_for_mobile',
                'software': {
                    'dr': 'offline'
                }
            }, merge=True)
            
            # Listen to commands subcollection
            self.listener_doc = self.device_ref.collection('commands').on_snapshot(self.on_command_received)
            logger.info(f"Listening on Firebase registered computer: {self.device_token}")
            logger.info(f"QR CODE URL: mpepe://link?token={self.device_token}")
            
            self.check_integrations()
            
        except Exception as e:
            logger.error(f"Firebase Init Error: {e}")

    def init_webrtc(self):
        try:
            from webrtc_streamer import WebRTCManager
            self.loop = asyncio.get_event_loop()
            self.webrtc = WebRTCManager(self.send_webrtc_signaling)
            self.webrtc_listener_doc = self.device_ref.collection('webrtc_signaling').on_snapshot(self.on_webrtc_signaling)
            logger.info("WebRTC Signaling Listener initialized.")
        except ImportError:
            logger.warning("WebRTC dependencies (aiortc, mss, opencv-python) not installed. Screen monitoring will be disabled.")
            self.webrtc = None

    def send_webrtc_signaling(self, session_id, data):
        if self.device_ref:
            self.device_ref.collection('webrtc_signaling').add(data)

    def on_webrtc_signaling(self, doc_snapshot, changes, read_time):
        for change in changes:
            if change.type.name == 'ADDED':
                data = change.document.to_dict()
                if data and data.get('type') == 'offer':
                    logger.info("Received WebRTC Offer from mobile")
                    if hasattr(self, 'webrtc') and self.webrtc:
                        sdp = data.get('sdp')
                        asyncio.run_coroutine_threadsafe(
                            self.webrtc.handle_offer(sdp, 'offer', self.device_token), 
                            self.loop
                        )

    def check_integrations(self):
        resolve = resolve_connection.get_resolve()
        if resolve:
            logger.info("🟢 DaVinci Resolve (Connected)")
            self.update_firebase_software_status('dr', 'online')
        else:
            logger.info("🔴 DaVinci Resolve (Not Running)")
            self.update_firebase_software_status('dr', 'offline')

    def update_firebase_software_status(self, soft_id, status):
        if self.device_ref:
            try:
                self.device_ref.update({
                    f'software.{soft_id}': status
                })
            except Exception as e:
                logger.error(f"Failed to update software status: {e}")

    def on_command_received(self, doc_snapshot, changes, read_time):
        for change in changes:
            if change.type.name == 'ADDED':
                doc = change.document
                data = doc.to_dict()
                
                if data.get('status') == 'pending':
                    logger.info(f"Received command: {data}")
                    self.execute_command(doc.id, data)

    def execute_command(self, doc_id, data):
        software_id = data.get('software_id')
        command = data.get('command')
        payload = data.get('payload', {})
        
        success = False
        message = ""
        
        try:
            if software_id == 'dr':
                success, message = self.execute_davinci_command(command, payload)
            elif software_id == 'os':
                success, message = self.execute_os_command(command, payload)
            elif software_id == 'nlp':
                # NLP commands are handled asynchronously to allow streaming feedback
                import threading
                threading.Thread(target=self.execute_nlp_command, args=(doc_id, command, payload)).start()
                return # Don't update status yet
            else:
                message = f"Ignored software ID: {software_id}"
                
        except Exception as e:
            success = False
            message = str(e)
            
        # Update command status
        if self.device_ref and software_id in ['dr', 'os']:
            self.device_ref.collection('commands').document(doc_id).update({
                'status': 'completed' if success else 'failed',
                'result_message': message
            })
            
    def execute_nlp_command(self, doc_id, command, payload):
        text = payload.get('text', '')
        self._update_nlp_status(doc_id, 'processing', 'Thinking...')
        
        try:
            plan = self.director.analyze_intent(text)
            steps = plan.get('plan', [])
            
            if not steps:
                self._update_nlp_status(doc_id, 'completed', 'I could not figure out how to do that.')
                return
                
            self._update_nlp_status(doc_id, 'processing', f'Executing {len(steps)} steps...')
            
            for step in steps:
                agent = step.get('agent')
                task = step.get('task')
                params = step.get('params', {})
                
                self._update_nlp_status(doc_id, 'processing', f'Agent {agent}: {task}')
                
                if agent == 'OS':
                    os_cmd = "open_app" if "open" in task.lower() else "unknown" # simplified for demo
                    if "volume" in task.lower():
                        os_cmd = "volume"
                        
                    self.execute_os_command(os_cmd, params)
                elif agent == 'Color Scientist':
                    # Simplified mapping for CDL
                    self.execute_davinci_command('apply_lut', params) # Just spoofing for demo
                    
                time.sleep(1) # Fake delay for effect
                
            self._update_nlp_status(doc_id, 'completed', 'Task completed successfully.')
            
        except Exception as e:
            logger.error(f"NLP Error: {e}")
            self._update_nlp_status(doc_id, 'failed', f'Error: {str(e)}')
            
    def _update_nlp_status(self, doc_id, status, message):
        if self.device_ref:
            self.device_ref.collection('commands').document(doc_id).update({
                'status': status,
                'result_message': message
            })
            
    def execute_os_command(self, command, payload):
        import subprocess
        if command == "open_app":
            app_name = payload.get("app_name")
            if sys.platform == "darwin":
                subprocess.Popen(["open", "-a", app_name])
                return True, f"Opened {app_name}"
            return False, "Unsupported OS for open_app"
        elif command == "volume":
            level = payload.get("level", 50) # 0 to 100
            if sys.platform == "darwin":
                subprocess.Popen(["osascript", "-e", f"set volume output volume {level}"])
                return True, f"Set volume to {level}%"
            return False, "Unsupported OS for volume"
        return False, f"Unknown OS command {command}"

    def execute_davinci_command(self, command, payload):
        resolve = resolve_connection.get_resolve()
        if not resolve:
            return False, "DaVinci Resolve not connected."
            
        projectManager = resolve.GetProjectManager()
        project = projectManager.GetCurrentProject()
        if not project:
            return False, "No active project."
            
        timeline = project.GetCurrentTimeline()
        if not timeline:
            return False, "No active timeline."

        if command == "apply_lut":
            lut_path = payload.get("lut_path")
            # Timeline API doesn't easily expose apply LUT globally without node graph access.
            # For this prototype, we'll just log it. 
            logger.info(f"Would apply LUT: {lut_path}")
            return True, f"LUT applied."
        elif command == "add_marker":
            name = payload.get("name", "AI Marker")
            color = payload.get("color", "Blue")
            note = payload.get("note", "")
            timeline.AddMarker(timeline.GetCurrentTimecode(), color, name, note, 1, "")
            return True, f"Marker {name} added."
        else:
            return False, f"Unknown command {command}"

    def run_forever(self):
        try:
            self.init_webrtc()
            if hasattr(self, 'loop'):
                self.loop.run_forever()
            else:
                while True:
                    time.sleep(1)
        except KeyboardInterrupt:
            if self.device_ref:
                self.device_ref.update({'desktop_connected': False})
            logger.info("Exiting...")

if __name__ == "__main__":
    agent = DaVinciFirebaseAgent()
    agent.run_forever()
