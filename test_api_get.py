import requests

url_base = "http://localhost:8000/api/v1/conversations/test-conv2/messages"
headers = {"x-user-id": "1", "Content-Type": "application/json"}
data = {
    "messages": [
        {
            "id": "3333",
            "sender": "user",
            "content": "test",
            "type": "image",
            "file_path": "/fake/path2.jpg",
            "file_name": "path2.jpg"
        }
    ]
}
requests.post(url_base + "/batch", json=data, headers=headers)

r = requests.get(url_base, headers=headers)
print(r.status_code, r.text)
