import requests

url = "http://localhost:8000/api/v1/conversations/test-conv/messages/batch"
headers = {"x-user-id": "1", "Content-Type": "application/json"}
data = {
    "messages": [
        {
            "id": "1111",
            "sender": "user",
            "content": "Hello",
            "type": "text",
            "file_path": "/fake/path.jpg",
            "file_name": "path.jpg"
        },
        {
            "id": "2222",
            "sender": "bot",
            "content": "Hi",
            "type": "text"
        }
    ]
}
r = requests.post(url, json=data, headers=headers)
print(r.status_code, r.text)

import sqlite3
conn = sqlite3.connect('e:/Projects/ai_chatbot_project/backend/chat.db')
cursor = conn.cursor()
cursor.execute("SELECT id, sender, type, file_path FROM messages WHERE conversation_id='test-conv'")
for row in cursor.fetchall():
    print(row)
