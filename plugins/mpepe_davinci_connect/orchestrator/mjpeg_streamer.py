import threading
import time
import io
import logging
from flask import Flask, Response

logger = logging.getLogger(__name__)

app = Flask(__name__)

def generate_frames():
    try:
        import mss
        from PIL import Image
    except ImportError:
        logger.error("mss or PIL not installed. Cannot stream video.")
        return
        
    with mss.mss() as sct:
        # Capture the primary monitor, or a specific region where DaVinci usually sits
        monitor = sct.monitors[1]
        
        # If you wanted to crop to center:
        # width, height = monitor["width"], monitor["height"]
        # bbox = {'top': int(height*0.1), 'left': int(width*0.2), 'width': int(width*0.6), 'height': int(height*0.5)}
        bbox = monitor
        
        while True:
            try:
                sct_img = sct.grab(bbox)
                img = Image.frombytes("RGB", sct_img.size, sct_img.bgra, "raw", "BGRX")
                
                # Resize down for performance to not overwhelm the UI
                img.thumbnail((640, 360))
                
                buf = io.BytesIO()
                img.save(buf, format='JPEG', quality=60)
                frame = buf.getvalue()
                
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
                time.sleep(0.05) # ~20 FPS
            except Exception as e:
                logger.error(f"Error grabbing frame: {e}")
                time.sleep(1)

@app.route('/stream')
def stream():
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

def start_streamer(port=5000):
    """Starts the Flask server in a daemon thread."""
    def run():
        # Hide flask startup messages
        import logging as fl_log
        log = fl_log.getLogger('werkzeug')
        log.setLevel(fl_log.ERROR)
        
        try:
            app.run(host='0.0.0.0', port=port, debug=False, use_reloader=False)
        except Exception as e:
            logger.error(f"Failed to start MJPEG streamer: {e}")
            
    t = threading.Thread(target=run, daemon=True)
    t.start()
    logger.info(f"Started MJPEG PIP Streamer on port {port}")
    return t

if __name__ == "__main__":
    start_streamer()
    while True:
        time.sleep(1)
