import os
import sys
import uuid
import time
import json
import logging
import asyncio
import threading

try:
    import firebase_admin
    from firebase_admin import credentials
    from firebase_admin import firestore
except ImportError:
    print("Please install firebase-admin: pip install firebase-admin")
    sys.exit(1)

# Plugin root (for the orchestrator/bridge packages) and this folder (for *_pb2 modules)
parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _p in (parent_dir, os.path.dirname(os.path.abspath(__file__))):
    if _p not in sys.path:
        sys.path.append(_p)

from bridge import resolve_connection

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
        provider = GeminiProvider(api_key=os.environ.get("GEMINI_API_KEY"),
                                  proxy_url=os.environ.get("CJ_GRADER_PROXY_URL"))
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
        """Plans the phone's request and runs it through the same Executor as the desktop UI."""
        from orchestrator.executor import create_task_bus

        text = payload.get('text', '')
        self._update_nlp_status(doc_id, 'processing', 'Thinking...')

        try:
            plan = self.director.analyze_intent(text, guided_mode=bool(payload.get('guided_mode', False)))
            steps = plan.get('plan', [])
            if plan.get('status') != 'success' or not steps:
                self._update_nlp_status(doc_id, 'completed',
                                        plan.get('message', 'I could not figure out how to do that.'))
                return

            for step in steps:
                for key in ('timeline_id', 'track_index', 'clip_index'):
                    if key in payload:
                        step[key] = payload[key]

            task_id = f"nlp_{doc_id}"[:40]
            bus = create_task_bus(task_id)
            self._update_nlp_status(doc_id, 'processing', f'Executing {len(steps)} steps...')

            # The phone has no confirm button yet, so a request sent from it counts as approval.
            # CDL steps still snapshot the grade first, so they can be undone from the ledger.
            outcome = {}
            worker = threading.Thread(
                target=lambda: outcome.update(self._executor().execute_plan(plan, task_id=task_id, auto_confirm=True)),
                daemon=True)
            worker.start()

            errors, last_detail = [], ''
            while True:
                event = bus.get()
                if event.get('status') == '__DONE__':
                    break
                label = f"Step {event.get('step_index')}/{event.get('total_steps')} {event.get('agent')}"
                if event['status'] == 'ERROR':
                    errors.append(f"{label}: {event.get('detail', '')}")
                elif event['status'] == 'DONE':
                    last_detail = event.get('detail', '')
                self._update_nlp_status(doc_id, 'processing',
                                        f"{label}: {event.get('task_description', '')} ({event['status'].lower()})")
            worker.join(timeout=5)

            if errors:
                self._update_nlp_status(doc_id, 'failed', ' | '.join(errors)[:900])
            else:
                self._update_nlp_status(doc_id, 'completed',
                                        f'Done: {len(steps)} step(s). {last_detail}'[:900])

        except Exception as e:
            logger.error(f"NLP Error: {e}")
            self._update_nlp_status(doc_id, 'failed', f'Error: {str(e)}')

    def _executor(self):
        if not hasattr(self, '_executor_instance'):
            from orchestrator.executor import Executor
            self._executor_instance = Executor()
        return self._executor_instance

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
            from bridge.tools.lut_tools import set_lut
            lut_path = payload.get("lut_path")
            if not lut_path:
                return False, "No lut_path given."
            ok = set_lut("", int(payload.get("track_index", 1)), int(payload.get("clip_index", 1)),
                         int(payload.get("node_index", 1)), lut_path)
            return ok, (f"LUT {lut_path} applied." if ok else f"Resolve could not apply {lut_path}.")
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
