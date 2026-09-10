import requests

API_KEY = "AIzaSyC7x52ADAM6rJZeiTJAeIYj-jdporiR8oA"
PROJECT_ID = "mpepe-2b4bd"

res = requests.post(
    f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}",
    json={"returnSecureToken": True}
)
data = res.json()
print("Auth:", data)
