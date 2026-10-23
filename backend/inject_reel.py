import os
import firebase_admin
from firebase_admin import credentials, firestore

cred_path = os.path.join(os.path.dirname(__file__), '..', 'plugins', 'mpepe_davinci_connect', 'python_bridge', 'serviceAccountKey.json')
cred = credentials.Certificate(cred_path)
firebase_admin.initialize_app(cred)
db = firestore.client()

# Posts collection - test reel post
post_ref = db.collection('posts').document('test_post_2_reel')
post_ref.set({
    'user_id': 'test_user_123',
    'content_type': 'reel',
    'media_urls': ['http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'],
    'aspect_ratio': 1.7777,
    'timestamp': firestore.SERVER_TIMESTAMP
})

print("Test reel injected successfully.")
