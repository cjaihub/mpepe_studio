import requests

url = "http://localhost:8000/api/upload"
video_path = "test_video.mp4"
post_id = "test_backend_processing_post"

with open(video_path, "rb") as f:
    files = {"file": (video_path, f, "video/mp4")}
    data = {"post_id": post_id}
    print("Uploading video...")
    response = requests.post(url, files=files, data=data)
    
print(f"Status Code: {response.status_code}")
print(f"Response: {response.json()}")
