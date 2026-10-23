import os
from fastapi import FastAPI, Query
from pydantic import BaseModel
from typing import Optional, List, Any
import firebase_admin
from firebase_admin import credentials, firestore

app = FastAPI(title="MPEPE Studio API")

cred_path = os.path.join(os.path.dirname(__file__), '..', 'plugins', 'mpepe_davinci_connect', 'python_bridge', 'serviceAccountKey.json')
if os.path.exists(cred_path):
    cred = credentials.Certificate(cred_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
    db = firestore.client()
else:
    print(f"Service account key not found at {cred_path}")
    db = None

class Post(BaseModel):
    id: str
    user_id: str
    content_type: str
    media_urls: List[str]
    thumbnail_url: Optional[str] = None
    processing_status: Optional[str] = None
    aspect_ratio: float
    timestamp: Any

@app.get("/api/feed", response_model=List[Post])
def get_feed(limit: int = 10, cursor: Optional[str] = None):
    if not db:
        return []
        
    query = db.collection('posts').order_by('timestamp', direction=firestore.Query.DESCENDING).limit(limit)
    
    if cursor:
        cursor_doc = db.collection('posts').document(cursor).get()
        if cursor_doc.exists:
            query = query.start_after(cursor_doc)
            
    docs = query.stream()
    
    feed = []
    for doc in docs:
        data = doc.to_dict()
        timestamp_val = data.get('timestamp')
        if hasattr(timestamp_val, 'isoformat'):
            timestamp_str = timestamp_val.isoformat()
        else:
            timestamp_str = str(timestamp_val)

        feed.append(Post(
            id=doc.id,
            user_id=data.get('user_id', ''),
            content_type=data.get('content_type', 'image'),
            media_urls=data.get('media_urls', []),
            thumbnail_url=data.get('thumbnail_url'),
            processing_status=data.get('processing_status'),
            aspect_ratio=data.get('aspect_ratio', 1.0),
            timestamp=timestamp_str
        ))
        
    return feed

from fastapi import UploadFile, File, Form, BackgroundTasks
import shutil
import uuid
from video_processor import extract_thumbnail, optimize_video_for_web
from firebase_admin import storage

def process_and_upload_video(file_path: str, post_id: str):
    try:
        if not db:
            print("DB not initialized, skipping processing")
            return
            
        base_dir = os.path.dirname(file_path)
        base_name = os.path.splitext(os.path.basename(file_path))[0]
        
        thumbnail_path = os.path.join(base_dir, f"{base_name}_thumb.jpg")
        optimized_path = os.path.join(base_dir, f"{base_name}_opt.mp4")
        
        # Process
        extract_thumbnail(file_path, thumbnail_path)
        optimize_video_for_web(file_path, optimized_path)
        
        # Upload to Firebase Storage
        bucket = storage.bucket('mpepe-2b4bd.firebasestorage.app')
        
        thumb_blob = bucket.blob(f"posts/{post_id}/thumbnail.jpg")
        thumb_blob.upload_from_filename(thumbnail_path, content_type='image/jpeg')
        thumb_blob.make_public()
        
        video_blob = bucket.blob(f"posts/{post_id}/optimized.mp4")
        video_blob.upload_from_filename(optimized_path, content_type='video/mp4')
        video_blob.make_public()
        
        # Update Firestore
        db.collection('posts').document(post_id).set({
            'thumbnail_url': thumb_blob.public_url,
            'media_urls': [video_blob.public_url],
            'content_url': video_blob.public_url,
            'processing_status': 'complete'
        }, merge=True)
        
        # Cleanup
        os.remove(file_path)
        os.remove(thumbnail_path)
        os.remove(optimized_path)
        
    except Exception as e:
        print(f"Error processing video: {e}")
        if db:
            db.collection('posts').document(post_id).set({
                'processing_status': 'error',
                'error_message': str(e)
            }, merge=True)

@app.post("/api/upload")
async def upload_video(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    post_id: str = Form(...)
):
    temp_dir = os.path.join(os.path.dirname(__file__), 'temp')
    os.makedirs(temp_dir, exist_ok=True)
    
    file_path = os.path.join(temp_dir, f"{uuid.uuid4()}_{file.filename}")
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    background_tasks.add_task(process_and_upload_video, file_path, post_id)
    
    return {"status": "ok", "message": "Video received and processing started"}

@app.get("/api/discover", response_model=List[Post])
def get_discover(limit: int = 20):
    if not db:
        return []
        
    query = db.collection('posts').where('processing_status', '==', 'complete').limit(limit * 2)
    docs = query.stream()
    
    feed = []
    for doc in docs:
        data = doc.to_dict()
        timestamp_val = data.get('timestamp')
        if hasattr(timestamp_val, 'isoformat'):
            timestamp_str = timestamp_val.isoformat()
        else:
            timestamp_str = str(timestamp_val)

        feed.append({
            'post': Post(
                id=doc.id,
                user_id=data.get('user_id', ''),
                content_type=data.get('content_type', 'image'),
                media_urls=data.get('media_urls', []),
                thumbnail_url=data.get('thumbnail_url'),
                processing_status=data.get('processing_status'),
                aspect_ratio=data.get('aspect_ratio', 1.0),
                timestamp=timestamp_str
            ),
            'likes': data.get('likes_count', 0),
            'ts': timestamp_str
        })
        
    # Sort in memory to avoid needing composite index in Firestore
    feed.sort(key=lambda x: (x['likes'], x['ts']), reverse=True)
    
    return [item['post'] for item in feed[:limit]]
