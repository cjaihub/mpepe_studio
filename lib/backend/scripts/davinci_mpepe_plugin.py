#!/usr/bin/env python3
"""
MPEPE Studio DaVinci Resolve Integration Plugin

This script runs inside DaVinci Resolve's Python environment.
It connects to the MPEPE Studio Flutter application via WebSocket and listens for commands
like applying LUTs, adding markers, or triggering renders.

Prerequisites:
- DaVinci Resolve Studio (Python API enabled)
- pip install websocket-client
"""

import os
import sys
import json
import time
import threading
try:
    import websocket
except ImportError:
    print("Please install websocket-client: pip install websocket-client")
    sys.exit(1)

# DaVinci Resolve API Setup
# Adjust the path if necessary depending on OS
try:
    import DaVinciResolveScript as dvr_script
    resolve = dvr_script.scriptapp("Resolve")
except ImportError:
    print("Could not load DaVinci Resolve API. Make sure you run this from within DaVinci.")
    resolve = None

WS_URL = "ws://127.0.0.1:8080"

def on_message(ws, message):
    print(f"[MPEPE Studio] Received: {message}")
    if not resolve:
        return
        
    try:
        data = json.loads(message)
        
        # We only care about commands
        if data.get("type") == "command":
            command = data.get("command")
            payload = data.get("payload", {})
            
            project_manager = resolve.GetProjectManager()
            project = project_manager.GetCurrentProject()
            if not project:
                return
                
            timeline = project.GetCurrentTimeline()
            if not timeline:
                return
            
            if command == "add_marker":
                frameId = timeline.GetCurrentTimecode() # Simplified for example
                # Get the frame ID from the timecode using a helper, for now just use 0 as an example or use playhead
                playhead = int(project.GetCurrentTimeline().GetCurrentTimecode()) # Note: actual conversion needed
                
                # timeline.AddMarker(frameId, color, name, note, duration, customData)
                timeline.AddMarker(
                    0, # placeholder frame 0
                    payload.get("color", "Blue"),
                    payload.get("name", "MPEPE Marker"),
                    payload.get("note", ""),
                    1,
                    ""
                )
                print("Marker added successfully.")
                
            elif command == "apply_lut":
                # Implementation depends on DaVinci version. Usually requires selecting a clip
                # and applying a LUT via the color page API.
                print(f"Applying LUT: {payload.get('lut_path')}")
                # Placeholder for Color Page API:
                # clip = timeline.GetCurrentVideoItem()
                # clip.SetLUT(payload.get('lut_path'))
    except Exception as e:
        print(f"Error handling message: {e}")

def on_error(ws, error):
    print(f"[MPEPE Studio] Error: {error}")

def on_close(ws, close_status_code, close_msg):
    print("[MPEPE Studio] Connection closed")

def on_open(ws):
    print("[MPEPE Studio] Connected to MPEPE Studio Native Bridge!")
    # Say hello
    ws.send(json.dumps({
        "type": "status",
        "client": "DaVinci Resolve",
        "status": "connected"
    }))

if __name__ == "__main__":
    print(f"Connecting to MPEPE Studio at {WS_URL}...")
    
    # We run the websocket in a thread so it doesn't freeze the DaVinci UI
    ws = websocket.WebSocketApp(WS_URL,
                              on_open=on_open,
                              on_message=on_message,
                              on_error=on_error,
                              on_close=on_close)
                              
    def run_ws():
        # Keeps trying to connect
        while True:
            ws.run_forever()
            time.sleep(5) # Reconnect delay
            
    ws_thread = threading.Thread(target=run_ws)
    ws_thread.daemon = True
    ws_thread.start()
    
    # Keep main thread alive
    while True:
        time.sleep(1)
