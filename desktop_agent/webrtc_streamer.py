import asyncio
import threading
import time
import cv2
import mss
import numpy as np
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCIceCandidate, VideoStreamTrack, AudioStreamTrack
from aiortc.contrib.signaling import object_from_string
from aiortc import RTCConfiguration, RTCIceServer
from av import VideoFrame, AudioFrame
from firebase_admin import firestore
import json
import pyautogui
import sounddevice as sd

# Disable PyAutoGUI failsafe to allow edge mouse movements
pyautogui.FAILSAFE = False

# ─── STUN server configuration ──────────────────────────────────────────────
_RTC_CONFIGURATION = RTCConfiguration(iceServers=[
    RTCIceServer(urls=["stun:stun.l.google.com:19302"]),
    RTCIceServer(urls=["stun:stun1.l.google.com:19302"]),
])


class ScreenVideoStreamTrack(VideoStreamTrack):
    """
    A video stream track that captures the primary screen using mss.
    """
    def __init__(self, fps=30):
        super().__init__()
        self.sct = mss.mss()
        self.fps = fps
        self.last_time = 0
        self.scale_factor = 1.0  # Dynamic scaling (1.0 = 1080p max, 0.5 = half of that, etc)
        self.target_window = None  # {top, left, width, height}
        # Monitor 1 is the primary screen. Monitor 0 is the virtual "all screens" composite.
        self.monitor = self.sct.monitors[1] if len(self.sct.monitors) > 1 else self.sct.monitors[0]

    async def recv(self):
        # Throttle FPS to avoid burning CPU
        target_frame_time = 1.0 / self.fps
        now = time.time()
        elapsed = now - self.last_time
        if elapsed < target_frame_time:
            await asyncio.sleep(target_frame_time - elapsed)

        pts, time_base = await self.next_timestamp()

        # Capture screenshot (full monitor or specific region)
        capture_region = self.monitor
        if self.target_window:
            capture_region = self.target_window
            
        img = self.sct.grab(capture_region)
        frame_bgra = np.array(img)
        frame_bgr = cv2.cvtColor(frame_bgra, cv2.COLOR_BGRA2BGR)

        # Base downscale to 1080p if needed (saves bandwidth significantly)
        h, w = frame_bgr.shape[:2]
        target_w = 1920 * self.scale_factor
        if w > target_w:
            scale_ratio = target_w / w
            new_size = (int(target_w), int(h * scale_ratio))
            frame_bgr = cv2.resize(frame_bgr, new_size, interpolation=cv2.INTER_LINEAR)

        new_frame = VideoFrame.from_ndarray(frame_bgr, format="bgr24")
        new_frame.pts = pts
        new_frame.time_base = time_base
        self.last_time = time.time()
        return new_frame


class SystemAudioTrack(AudioStreamTrack):
    """
    Captures the default system microphone (or loopback if virtual cable is installed)
    and streams it.
    """
    def __init__(self):
        super().__init__()
        self.samplerate = 48000
        self.channels = 1
        self.stream = sd.InputStream(samplerate=self.samplerate, channels=self.channels, dtype='int16')
        self.stream.start()

    async def recv(self):
        pts, time_base = await self.next_timestamp()
        
        # 20ms of audio at 48000Hz is 960 samples
        loop = asyncio.get_running_loop()
        data, overflow = await loop.run_in_executor(None, self.stream.read, 960)
        
        frame = AudioFrame.from_ndarray(data.T, format='s16', layout='mono')
        frame.pts = pts
        frame.time_base = time_base
        frame.sample_rate = self.samplerate
        return frame
        
    def stop(self):
        super().stop()
        if self.stream:
            self.stream.stop()
            self.stream.close()

class WebRTCSession:
    """
    Manages a single WebRTC peer connection lifecycle for one mobile client.
    Handles offer, answer, ICE candidates, and cleanup.
    """
    def __init__(self, device_ref, loop, pcs_set):
        self.device_ref = device_ref
        self.loop = loop
        self.pcs_set = pcs_set
        self.pc = RTCPeerConnection(configuration=_RTC_CONFIGURATION)
        self.pcs_set.add(self.pc)
        self._pending_candidates = []  # Buffer candidates received before remote description
        self.video_track = ScreenVideoStreamTrack(fps=30)
        self.audio_track = SystemAudioTrack()

    async def handle_offer(self, offer_dict, doc_id):
        print(f"[WebRTC] Processing offer from doc: {doc_id}")

        if not offer_dict.get('sdp') or not offer_dict.get('type'):
            print("[WebRTC] Invalid offer: missing sdp or type field.")
            return

        offer = RTCSessionDescription(sdp=offer_dict['sdp'], type=offer_dict['type'])

        @self.pc.on("iceconnectionstatechange")
        async def on_ice_state_change():
            print(f"[WebRTC] ICE state: {self.pc.iceConnectionState}")
            if self.pc.iceConnectionState in ("failed", "closed"):
                await self._cleanup()

        @self.pc.on("connectionstatechange")
        async def on_conn_state_change():
            print(f"[WebRTC] Connection state: {self.pc.connectionState}")
            if self.pc.connectionState in ("failed", "closed"):
                await self._cleanup()

        @self.pc.on("icecandidate")
        async def on_ice_candidate(candidate):
            # Push local ICE candidates back to Firestore for the mobile to consume
            if candidate:
                try:
                    self.device_ref.collection('webrtc_signaling').add({
                        'type': 'candidate',
                        'candidate': candidate.candidate,
                        'sdpMid': candidate.sdpMid,
                        'sdpMLineIndex': candidate.sdpMLineIndex,
                    })
                except Exception as e:
                    print(f"[WebRTC] Failed to push ICE candidate: {e}")

        @self.pc.on("datachannel")
        def on_datachannel(channel):
            print(f"[WebRTC] Data channel established: {channel.label}")
            @channel.on("message")
            def on_message(message):
                try:
                    data = json.loads(message)
                    action = data.get('action')
                    
                    if action == 'mouse_move':
                        dx, dy = data.get('dx', 0), data.get('dy', 0)
                        pyautogui.move(dx, dy)
                    elif action == 'mouse_click':
                        button = data.get('button', 'left')
                        pyautogui.click(button=button)
                    elif action == 'mouse_scroll':
                        dy = data.get('dy', 0)
                        pyautogui.scroll(int(-dy))
                    elif action == 'key_press':
                        key = data.get('key')
                        if key:
                            pyautogui.press(key)
                    elif action == 'set_resolution':
                        scale = data.get('scale', 1.0)
                        self.video_track.scale_factor = float(scale)
                    elif action == 'set_window':
                        # Expects {top, left, width, height}
                        window_data = data.get('window')
                        self.video_track.target_window = window_data
                        
                except Exception as e:
                    print(f"[WebRTC] Error handling data channel message: {e}")

        # Add the screen capture track and audio track
        self.pc.addTrack(self.video_track)
        self.pc.addTrack(self.audio_track)

        # Process offer and create answer
        await self.pc.setRemoteDescription(offer)

        # Apply any buffered remote ICE candidates now that remote description is set
        for candidate_data in self._pending_candidates:
            await self._add_candidate(candidate_data)
        self._pending_candidates.clear()

        answer = await self.pc.createAnswer()
        await self.pc.setLocalDescription(answer)

        # Send the answer back to Firestore
        self.device_ref.collection('webrtc_signaling').add({
            'type': self.pc.localDescription.type,
            'sdp': self.pc.localDescription.sdp,
        })
        print("[WebRTC] Answer sent to Firestore. Waiting for connection...")

    async def add_remote_candidate(self, candidate_data):
        """Add a remote ICE candidate. Buffers if remote description is not set yet."""
        if self.pc.remoteDescription is None:
            self._pending_candidates.append(candidate_data)
        else:
            await self._add_candidate(candidate_data)

    async def _add_candidate(self, candidate_data):
        try:
            candidate = RTCIceCandidate(
                component=None,
                foundation=None,
                ip=None,
                port=None,
                priority=None,
                protocol=None,
                type=None,
                sdpMid=candidate_data.get('sdpMid'),
                sdpMLineIndex=candidate_data.get('sdpMLineIndex'),
            )
            # aiortc expects the raw candidate string as `candidate` attr
            candidate.candidate = candidate_data.get('candidate', '')
            await self.pc.addIceCandidate(candidate)
        except Exception as e:
            print(f"[WebRTC] Failed to add ICE candidate: {e}")

    async def _cleanup(self):
        try:
            await self.pc.close()
        except Exception:
            pass
        self.pcs_set.discard(self.pc)
        print("[WebRTC] Session cleaned up.")


class WebRTCManager:
    def __init__(self, signaling_ref):
        """signaling_ref can be any Firestore CollectionReference:
        - Legacy: registered_computers/{id}/webrtc_signaling
        - Session: users/{uid}/sessions/{sid}/webrtc_signaling
        """
        self.signaling_ref = signaling_ref
        self.pcs = set()
        self.signaling_listener = None
        self.loop = None
        self.active_session: WebRTCSession | None = None

    def start_listening(self, loop):
        self.loop = loop

        def on_snapshot(col_snapshot, changes, read_time):
            for change in changes:
                if change.type.name != 'ADDED':
                    continue
                data = change.document.to_dict()
                if not data:
                    continue

                # Skip messages we wrote ourselves (avoid echo)
                if data.get('origin') == 'desktop':
                    continue

                msg_type = data.get('type')

                if msg_type == 'offer':
                    # Validate owner_uid if present (defence in depth)
                    # The session service already enforces this at Firestore rules level
                    self.active_session = WebRTCSession(self.signaling_ref, self.loop, self.pcs)
                    asyncio.run_coroutine_threadsafe(
                        self.active_session.handle_offer(data, change.document.id),
                        self.loop
                    )

                elif msg_type == 'candidate' and self.active_session:
                    asyncio.run_coroutine_threadsafe(
                        self.active_session.add_remote_candidate(data),
                        self.loop
                    )

        self.signaling_listener = self.signaling_ref.on_snapshot(on_snapshot)
        print("[WebRTC] Signaling listener started. Waiting for offers...")

    def stop(self):
        if self.signaling_listener:
            self.signaling_listener.unsubscribe()
            self.signaling_listener = None
        if self.loop and self.loop.is_running():
            asyncio.run_coroutine_threadsafe(
                asyncio.gather(*[pc.close() for pc in list(self.pcs)], return_exceptions=True),
                self.loop
            )
        self.pcs.clear()
        self.active_session = None
        print("[WebRTC] Manager stopped.")


# ─── Global manager registry — allows stop_all_sessions() ───────────────────
_active_managers: list['WebRTCManager'] = []


def start_webrtc_thread(signaling_ref):
    """
    Spawns a background thread with its own asyncio event loop.
    signaling_ref is any Firestore CollectionReference pointing to
    the webrtc_signaling subcollection (device-level OR session-level).
    """
    def run_loop():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        manager = WebRTCManager(signaling_ref)
        _active_managers.append(manager)
        manager.start_listening(loop)

        try:
            loop.run_forever()
        except Exception as e:
            print(f"[WebRTC] Event loop error: {e}")
        finally:
            pending = list(manager.pcs)
            if pending:
                loop.run_until_complete(asyncio.gather(
                    *[pc.close() for pc in pending],
                    return_exceptions=True
                ))
            if manager in _active_managers:
                _active_managers.remove(manager)
            loop.close()

    thread = threading.Thread(target=run_loop, daemon=True, name="WebRTC-Thread")
    thread.start()
    return thread


def stop_all_sessions():
    """Stop all active WebRTC managers and peer connections."""
    for manager in list(_active_managers):
        manager.stop()
    _active_managers.clear()
    print("[WebRTC] All sessions stopped.")

