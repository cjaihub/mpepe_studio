import os
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import firebase_admin
from firebase_admin import credentials, firestore
import urllib.parse

cred_path = os.path.join(os.path.dirname(__file__), '..', 'plugins', 'mpepe_davinci_connect', 'python_bridge', 'serviceAccountKey.json')
if os.path.exists(cred_path):
    cred = credentials.Certificate(cred_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
    db = firestore.client()
else:
    db = None

class FeedHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/feed'):
            if not db:
                self.send_response(500)
                self.end_headers()
                return

            query = db.collection('posts').order_by('timestamp', direction=firestore.Query.DESCENDING).limit(10)
            docs = query.stream()
            feed = []
            for doc in docs:
                data = doc.to_dict()
                feed.append({
                    'id': doc.id,
                    'user_id': data.get('user_id', ''),
                    'content_type': data.get('content_type', 'image'),
                    'media_urls': data.get('media_urls', []),
                    'aspect_ratio': data.get('aspect_ratio', 1.0),
                    'timestamp': str(data.get('timestamp'))
                })
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(feed).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8000), FeedHandler)
    print("Starting server on port 8000...")
    server.serve_forever()
