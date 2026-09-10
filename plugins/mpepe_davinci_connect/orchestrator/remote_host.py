import asyncio
import websockets
import json
import logging
import io
import mss
import pyautogui
from PIL import Image

logger = logging.getLogger(__name__)

class RemoteHost:
    def __init__(self, port=8080):
        self.port = port
        self.clients = set()
        pyautogui.FAILSAFE = False

    async def broadcast_screen(self):
        with mss.mss() as sct:
            monitor = sct.monitors[1]
            while True:
                if self.clients:
                    try:
                        sct_img = sct.grab(monitor)
                        img = Image.frombytes("RGB", sct_img.size, sct_img.bgra, "raw", "BGRX")
                        img.thumbnail((1280, 720)) # Resize for bandwidth
                        buf = io.BytesIO()
                        img.save(buf, format='JPEG', quality=50)
                        frame_bytes = buf.getvalue()
                        
                        disconnected = set()
                        for client in self.clients:
                            try:
                                await client.send(frame_bytes)
                            except websockets.ConnectionClosed:
                                disconnected.add(client)
                        self.clients -= disconnected
                    except Exception as e:
                        logger.error(f"Error broadcasting frame: {e}")
                await asyncio.sleep(0.05) # ~20 FPS

    async def handle_client(self, websocket, path):
        self.clients.add(websocket)
        logger.info(f"Client connected for remote control. Total: {len(self.clients)}")
        try:
            async for message in websocket:
                if isinstance(message, str):
                    try:
                        data = json.loads(message)
                        self.execute_command(data)
                    except json.JSONDecodeError:
                        logger.warning("Received invalid JSON command")
        except websockets.ConnectionClosed:
            pass
        finally:
            self.clients.remove(websocket)
            logger.info("Client disconnected.")

    def execute_command(self, data):
        cmd = data.get("type")
        if cmd == "MOUSE_MOVE":
            # Map normalized coordinates (0.0 to 1.0) to screen coordinates
            x_norm = data.get("x", 0.5)
            y_norm = data.get("y", 0.5)
            screen_width, screen_height = pyautogui.size()
            target_x = int(x_norm * screen_width)
            target_y = int(y_norm * screen_height)
            pyautogui.moveTo(target_x, target_y, duration=0.1)
        elif cmd == "CLICK":
            pyautogui.click()
        elif cmd == "DOUBLE_CLICK":
            pyautogui.doubleClick()
        elif cmd == "RIGHT_CLICK":
            pyautogui.rightClick()
        elif cmd == "TYPE":
            text = data.get("text", "")
            if text:
                pyautogui.write(text, interval=0.01)
        elif cmd == "PRESS":
            key = data.get("key", "")
            if key:
                pyautogui.press(key)

    async def start_server(self):
        logger.info(f"Starting Remote Control WebSocket Server on port {self.port}...")
        server = await websockets.serve(self.handle_client, "0.0.0.0", self.port)
        await asyncio.gather(
            server.wait_closed(),
            self.broadcast_screen()
        )

def start_remote_host(port=8080):
    import threading
    host = RemoteHost(port=port)
    def run():
        # Requires its own event loop since it's running in a thread
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(host.start_server())
    t = threading.Thread(target=run, daemon=True)
    t.start()
    return t

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    start_remote_host()
    import time
    while True:
        time.sleep(1)
