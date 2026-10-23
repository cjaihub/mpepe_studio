import os
import time
import firebase_admin
from firebase_admin import credentials, firestore

cred_path = os.path.join(os.path.dirname(__file__), '..', 'plugins', 'mpepe_davinci_connect', 'python_bridge', 'serviceAccountKey.json')
cred = credentials.Certificate(cred_path)
firebase_admin.initialize_app(cred)
db = firestore.client()

# Users collection - test user
user_ref = db.collection('users').document('test_user_123')
user_ref.set({
    'username': 'mpepe_creator',
    'display_name': 'Mpepe Creator',
    'profile_url': 'https://example.com/profile.png'
})

# Posts collection - test post
post_ref = db.collection('posts').document('test_post_1')
post_ref.set({
    'user_id': 'test_user_123',
    'content_type': 'image',
    'media_urls': ['https://example.com/test_image.png'],
    'aspect_ratio': 1.0,
    'timestamp': firestore.SERVER_TIMESTAMP
})

print("Test user and post injected successfully.")
