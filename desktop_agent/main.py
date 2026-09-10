import os
import sys
import uuid
import threading
import json
import customtkinter as ctk
from PIL import Image
import qrcode

try:
    import firebase_admin
    from firebase_admin import credentials
    from firebase_admin import firestore
except ImportError:
    print("Please install firebase-admin: pip install firebase-admin")
    sys.exit(1)

# Import our bridges
import premiere_bridge
import davinci_bridge

import socket

class MpepeConnectAgent(ctk.CTk):
    def __init__(self):
        super().__init__()
        
        self.title("MPEPE Studio Connect")
        self.geometry("400x600")
        self.resizable(False, False)
        
        # Appearance
        ctk.set_appearance_mode("dark")
        
        # MPEPE Brand Colors
        self.bg_color = "#0A0A0A"
        self.surface_color = "#141414"
        self.primary_color = "#990000"
        self.text_color = "#F3F4F6"
        self.muted_color = "#9CA3AF"
        
        self.configure(fg_color=self.bg_color)
        
        self.device_token = self.load_or_create_token()
        self.computer_name = socket.gethostname()
        self.db = None
        self.device_ref = None
        self.listener_doc = None
        
        self.setup_ui()
        self.init_firebase()

    def get_resource_path(self, relative_path):
        """ Get absolute path to resource, works for dev and for PyInstaller """
        try:
            # PyInstaller creates a temp folder and stores path in _MEIPASS
            base_path = sys._MEIPASS
        except Exception:
            base_path = os.path.abspath(".")
        return os.path.join(base_path, relative_path)

    def get_app_data_path(self):
        """ Get a writable directory for config files """
        home = os.path.expanduser("~")
        app_dir = os.path.join(home, ".mpepe_connect")
        if not os.path.exists(app_dir):
            os.makedirs(app_dir)
        return app_dir

    def load_or_create_token(self):
        config_path = os.path.join(self.get_app_data_path(), "device_config.json")
        if os.path.exists(config_path):
            with open(config_path, "r") as f:
                data = json.load(f)
                return data.get("device_token", str(uuid.uuid4()))
        else:
            token = str(uuid.uuid4())
            with open(config_path, "w") as f:
                json.dump({"device_token": token}, f)
            return token

    def setup_ui(self):
        # Header
        self.lbl_title = ctk.CTkLabel(self, text="MPEPE Studio Connect", font=ctk.CTkFont(family="Inter", size=22, weight="bold"), text_color=self.text_color)
        self.lbl_title.pack(pady=(30, 5))
        
        self.lbl_subtitle = ctk.CTkLabel(self, text="Scan with MPEPE Studio App", font=ctk.CTkFont(family="Inter", size=13), text_color=self.muted_color)
        self.lbl_subtitle.pack(pady=(0, 20))
        
        # QR Code
        qr_data = f"mpepe://link?token={self.device_token}"
        qr = qrcode.QRCode(box_size=10, border=2)
        qr.add_data(qr_data)
        qr.make(fit=True)
        # Using MPEPE maroon for QR code with dark background
        img = qr.make_image(fill_color="#990000", back_color="#141414")
        
        # Save temp image for CTkImage
        img_path = "temp_qr.png"
        img.save(img_path)
        
        self.qr_image = ctk.CTkImage(light_image=Image.open(img_path),
                                     dark_image=Image.open(img_path),
                                     size=(220, 220))
        
        self.lbl_qr = ctk.CTkLabel(self, image=self.qr_image, text="")
        self.lbl_qr.pack(pady=20)
        
        # Remove temp image
        if os.path.exists(img_path):
            os.remove(img_path)
            
        self.lbl_device = ctk.CTkLabel(self, text=f"Token: {self.device_token[:12]}...", font=ctk.CTkFont(family="Inter", size=14, weight="bold"), text_color=self.text_color)
        self.lbl_device.pack(pady=(0, 20))
        
        # Status Frame
        self.status_frame = ctk.CTkFrame(self, fg_color=self.surface_color, corner_radius=12)
        self.status_frame.pack(fill="x", padx=30, pady=10)
        
        self.lbl_status_title = ctk.CTkLabel(self.status_frame, text="Active Integrations", font=ctk.CTkFont(family="Inter", size=14, weight="bold"), text_color=self.text_color)
        self.lbl_status_title.pack(pady=(15, 10))
        
        # Premiere Status
        self.pr_status_var = ctk.StringVar(value="⚫ Checking...")
        self.lbl_pr = ctk.CTkLabel(self.status_frame, textvariable=self.pr_status_var, font=ctk.CTkFont(family="Inter", size=12), text_color=self.muted_color)
        self.lbl_pr.pack(pady=5, padx=20, anchor="w")
        
        # DaVinci Status
        self.dr_status_var = ctk.StringVar(value="⚫ Checking...")
        self.lbl_dr = ctk.CTkLabel(self.status_frame, textvariable=self.dr_status_var, font=ctk.CTkFont(family="Inter", size=12), text_color=self.muted_color)
        self.lbl_dr.pack(pady=(5, 15), padx=20, anchor="w")
        
        self.btn_refresh = ctk.CTkButton(self, text="Refresh Status", command=self.check_integrations, fg_color=self.primary_color, hover_color="#7A0000", font=ctk.CTkFont(family="Inter", weight="bold"), corner_radius=8)
        self.btn_refresh.pack(pady=20)
        
        self.check_integrations()

    def init_firebase(self):
        cred_path = self.get_resource_path("serviceAccountKey.json")
        if not os.path.exists(cred_path):
            # Fallback for local development
            cred_path = "serviceAccountKey.json"
            if not os.path.exists(cred_path):
                print(f"Error: {cred_path} not found. Please add your Firebase service account key.")
                self.lbl_subtitle.configure(text="Missing serviceAccountKey.json!", text_color="#FF4C4C")
                return
            
        try:
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            self.db = firestore.client()
            
            # Create device document
            self.device_ref = self.db.collection('registered_computers').document(self.device_token)
            self.device_ref.set({
                'computer_name': self.computer_name,
                'desktop_connected': True,
                'status': 'waiting_for_mobile',
                'software': {
                    'pr': 'offline',
                    'dr': 'offline'
                }
            }, merge=True)
            
            # Listen to commands subcollection
            self.listener_doc = self.device_ref.collection('commands').on_snapshot(self.on_command_received)
            print(f"Listening on Firebase registered computer: {self.device_token}")
            self.lbl_subtitle.configure(text="Waiting for mobile connection...", text_color="green")
            
        except Exception as e:
            print(f"Firebase Init Error: {e}")
            self.lbl_subtitle.configure(text="Firebase Connection Error", text_color="red")

    def check_integrations(self):
        # Check Premiere
        if premiere_bridge.is_running():
            self.pr_status_var.set("🟢 Premiere Pro (Connected)")
            self.update_firebase_software_status('pr', 'online')
        else:
            self.pr_status_var.set("🔴 Premiere Pro (Not Running)")
            self.update_firebase_software_status('pr', 'offline')
            
        # Check DaVinci
        if davinci_bridge.is_running():
            self.dr_status_var.set("🟢 DaVinci Resolve (Connected)")
            self.update_firebase_software_status('dr', 'online')
        else:
            self.dr_status_var.set("🔴 DaVinci Resolve (Not Running)")
            self.update_firebase_software_status('dr', 'offline')

    def update_firebase_software_status(self, soft_id, status):
        if self.device_ref:
            try:
                self.device_ref.update({
                    f'software.{soft_id}': status
                })
            except Exception as e:
                pass

    def on_command_received(self, doc_snapshot, changes, read_time):
        for change in changes:
            if change.type.name == 'ADDED':
                doc = change.document
                data = doc.to_dict()
                
                if data.get('status') == 'pending':
                    print(f"Received command: {data}")
                    self.execute_command(doc.id, data)

    def execute_command(self, doc_id, data):
        software_id = data.get('software_id')
        command = data.get('command')
        payload = data.get('payload', {})
        
        success = False
        message = ""
        
        try:
            if software_id == 'pr':
                success, message = premiere_bridge.execute(command, payload)
            elif software_id == 'dr':
                success, message = davinci_bridge.execute(command, payload)
            else:
                message = f"Unknown software ID: {software_id}"
                
        except Exception as e:
            success = False
            message = str(e)
            
        # Update command status
        if self.device_ref:
            self.device_ref.collection('commands').document(doc_id).update({
                'status': 'completed' if success else 'failed',
                'result_message': message
            })
            
    def on_closing(self):
        if self.device_ref:
            self.device_ref.update({'desktop_connected': False})
        self.destroy()

if __name__ == "__main__":
    app = MpepeConnectAgent()
    app.protocol("WM_DELETE_WINDOW", app.on_closing)
    app.mainloop()
