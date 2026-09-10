import asyncio
import logging
import cv2
import numpy as np
import mss
from av import VideoFrame
from aiortc import RTCPeerConnection, RTCSessionDescription, VideoStreamTrack
from aiortc.contrib.media import MediaRelay

logger = logging.getLogger(__name__)

class ScreenCaptureTrack(VideoStreamTrack):
    """
    A video stream track that captures the desktop screen using mss.
    """
    def __init__(self, fps=15):
        super().__init__()
        self.sct = mss.mss()
        self.monitor = self.sct.monitors[1]  # Capture the primary monitor
        self.fps = fps
        self._start_time = None

    async def recv(self):
        pts, time_base = await self.next_timestamp()
        
        # Grab screen
        sct_img = self.sct.grab(self.monitor)
        
        # Convert to numpy array and drop alpha channel (BGRA -> BGR)
        img = np.array(sct_img)
        img_bgr = img[:, :, :3]
        
        # Convert to YUV420p for WebRTC
        # aiortc handles BGR24 -> YUV via pyav if we create a frame like this
        frame = VideoFrame.from_ndarray(img_bgr, format="bgr24")
        frame.pts = pts
        frame.time_base = time_base
        
        # We need to yield control periodically for fps pacing. aiortc handles the timing 
        # largely through the timestamps, but a small sleep avoids spinning.
        await asyncio.sleep(1 / self.fps)
        
        return frame

class WebRTCManager:
    def __init__(self, signaling_callback):
        self.pcs = set()
        self.signaling_callback = signaling_callback

    async def handle_offer(self, sdp, type, session_id):
        pc = RTCPeerConnection()
        self.pcs.add(pc)

        @pc.on("connectionstatechange")
        async def on_connectionstatechange():
            logger.info(f"WebRTC Connection state is {pc.connectionState}")
            if pc.connectionState == "failed" or pc.connectionState == "closed":
                await pc.close()
                self.pcs.discard(pc)

        # Add the screen track
        track = ScreenCaptureTrack(fps=15)
        pc.addTrack(track)

        # Set remote description (offer)
        offer = RTCSessionDescription(sdp=sdp, type=type)
        await pc.setRemoteDescription(offer)

        # Create local description (answer)
        answer = await pc.createAnswer()
        await pc.setLocalDescription(answer)

        # Send answer back to mobile via Firebase
        self.signaling_callback(session_id, {
            'sdp': pc.localDescription.sdp,
            'type': pc.localDescription.type
        })

    async def close_all(self):
        coros = [pc.close() for pc in self.pcs]
        await asyncio.gather(*coros)
        self.pcs.clear()
