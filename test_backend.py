"""
Maveric AI — Automated Backend API Test Suite
Covers tests 1-13 at the API level (independent of UI).
Run from: e:\Projects\ai_chatbot_project\backend
Usage:  python ..\test_backend.py
"""
import requests
import json
import sys
import time
import os

BASE = "http://localhost:8000"
PASS = "\033[92m[PASS]\033[0m"
FAIL = "\033[91m[FAIL]\033[0m"
SKIP = "\033[93m[SKIP]\033[0m"
results = {}

def check(name, passed, detail=""):
    status = PASS if passed else FAIL
    results[name] = passed
    print(f"{status} {name}" + (f" — {detail}" if detail else ""))
    return passed

# ─────────────────────────────────────────────────────────────
# TEST 1: Register new account
# ─────────────────────────────────────────────────────────────
ts = int(time.time())
email = f"testuser_{ts}@maveric.ai"
password = "Test@1234"
name = f"Test User {ts}"

print("\n===== TEST 1: Register new account =====")
r = requests.post(f"{BASE}/api/v1/auth/register", json={"name": name, "email": email, "password": password})
ok = r.status_code == 201 and "access_token" in r.json()
check("Register new account", ok, f"status={r.status_code}")

access_token = r.json().get("access_token", "")
refresh_token = r.json().get("refresh_token", "")
user_id = r.json().get("user_id")

# ─────────────────────────────────────────────────────────────
# TEST 2: Duplicate registration should fail
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 2: Duplicate registration blocked =====")
r2 = requests.post(f"{BASE}/api/v1/auth/register", json={"name": name, "email": email, "password": password})
check("Duplicate email blocked", r2.status_code == 400, f"status={r2.status_code}")

# ─────────────────────────────────────────────────────────────
# TEST 3: Login with same account
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 3: Login =====")
r3 = requests.post(f"{BASE}/api/v1/auth/login", json={"email": email, "password": password})
ok3 = r3.status_code == 200 and "access_token" in r3.json()
check("Login with registered account", ok3, f"status={r3.status_code}")
access_token = r3.json().get("access_token", access_token)
refresh_token = r3.json().get("refresh_token", refresh_token)
user_id = r3.json().get("user_id", user_id)

# ─────────────────────────────────────────────────────────────
# TEST 4: Token refresh
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 4: Token refresh =====")
r4 = requests.post(f"{BASE}/api/v1/auth/refresh", json={"refresh_token": refresh_token})
ok4 = r4.status_code == 200 and "access_token" in r4.json()
check("Token refresh returns new access token", ok4, f"status={r4.status_code}")
if ok4:
    access_token = r4.json()["access_token"]

# ─────────────────────────────────────────────────────────────
# TEST 5: /me endpoint
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 5: /me endpoint =====")
headers = {"Authorization": f"Bearer {access_token}"}
r5 = requests.get(f"{BASE}/api/v1/auth/me", headers=headers)
ok5 = r5.status_code == 200 and r5.json().get("email") == email
check("/me returns correct user", ok5, f"status={r5.status_code} email={r5.json().get('email','?')}")

# ─────────────────────────────────────────────────────────────
# TEST 6: Create conversation
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 6: Create conversation =====")
conv_id = f"conv_{ts}"
r6 = requests.post(f"{BASE}/api/v1/conversations", json={"id": conv_id, "title": "Test Chat"}, headers=headers)
ok6 = r6.status_code in (200, 201)
check("Create conversation", ok6, f"status={r6.status_code}")

# ─────────────────────────────────────────────────────────────
# TEST 7: Send chat message
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 7: Send chat message =====")
r7 = requests.post(f"{BASE}/chat", json={"message": "What is 2+2?", "user_id": user_id, "conversation_id": conv_id}, headers=headers)
ok7 = r7.status_code == 200 and len(r7.json().get("reply", "")) > 0
check("Chat returns reply", ok7, f"status={r7.status_code} reply_len={len(r7.json().get('reply',''))}")

# ─────────────────────────────────────────────────────────────
# TEST 8: Batch save messages
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 8: Batch save messages =====")
batch = {
    "messages": [
        {"id": f"msg_user_{ts}", "sender": "user", "content": "What is 2+2?", "type": "text"},
        {"id": f"msg_bot_{ts}",  "sender": "bot",  "content": "4",             "type": "text"},
    ]
}
r8 = requests.post(f"{BASE}/api/v1/conversations/{conv_id}/messages/batch", json=batch, headers=headers)
ok8 = r8.status_code in (200, 201) and r8.json().get("saved", 0) == 2
check("Batch save 2 messages", ok8, f"status={r8.status_code} saved={r8.json().get('saved','?')}")

# ─────────────────────────────────────────────────────────────
# TEST 9: Load conversation history (restore after login)
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 9: Restore conversation history =====")
r9 = requests.get(f"{BASE}/api/v1/conversations", headers=headers)
ok9 = r9.status_code == 200 and any(c["id"] == conv_id for c in r9.json())
check("Conversation list includes our conv", ok9, f"count={len(r9.json())}")

r9b = requests.get(f"{BASE}/api/v1/conversations/{conv_id}", headers=headers)
ok9b = r9b.status_code == 200 and len(r9b.json().get("messages", [])) >= 2
check("Conversation detail has saved messages", ok9b, f"msg_count={len(r9b.json().get('messages',[]))}")

# ─────────────────────────────────────────────────────────────
# TEST 10: Rename conversation
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 10: Rename conversation =====")
r10 = requests.put(f"{BASE}/api/v1/conversations/{conv_id}", json={"title": "Renamed Chat"}, headers=headers)
ok10 = r10.status_code == 200 and r10.json().get("title") == "Renamed Chat"
check("Rename conversation", ok10, f"status={r10.status_code} title={r10.json().get('title','?')}")

# ─────────────────────────────────────────────────────────────
# TEST 11: Delete conversation
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 11: Delete conversation =====")
r11 = requests.delete(f"{BASE}/api/v1/conversations/{conv_id}", headers=headers)
ok11 = r11.status_code == 200

# Verify it's gone
r11b = requests.get(f"{BASE}/api/v1/conversations/{conv_id}", headers=headers)
ok11b = r11b.status_code == 404

check("Delete conversation returns 200", ok11, f"status={r11.status_code}")
check("Deleted conversation returns 404", ok11b, f"status={r11b.status_code}")

# ─────────────────────────────────────────────────────────────
# TEST 12: Upload and extract text from a PDF/document
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 12: Upload document =====")
# Create a small test text file
test_file_path = "test_doc.txt"
with open(test_file_path, "w") as f:
    f.write("The capital of France is Paris. The Eiffel Tower is in Paris.")

with open(test_file_path, "rb") as f:
    r12 = requests.post(f"{BASE}/upload-attachment", files={"file": ("test_doc.txt", f, "text/plain")}, headers={"Authorization": f"Bearer {access_token}"})

ok12 = r12.status_code == 200 and "Paris" in (r12.json().get("extracted_text") or "")
check("Upload doc extracts text", ok12, f"status={r12.status_code} text_len={len(r12.json().get('extracted_text',''))}")
os.remove(test_file_path)

# TEST 12b: Ask question about document
if ok12:
    doc_text = r12.json()["extracted_text"]
    r12b = requests.post(f"{BASE}/chat", json={
        "message": "What city is mentioned?",
        "user_id": user_id,
        "file_text": doc_text,
        "file_name": "test_doc.txt"
    }, headers=headers)
    ok12b = r12b.status_code == 200 and "paris" in r12b.json().get("reply", "").lower()
    check("Doc QA returns content-based answer", ok12b, f"reply={r12b.json().get('reply','')[:80]}")

# ─────────────────────────────────────────────────────────────
# TEST 13: Wrong password login is rejected
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 13: Invalid credentials rejected =====")
r13 = requests.post(f"{BASE}/api/v1/auth/login", json={"email": email, "password": "wrongpassword"})
check("Wrong password rejected with 401", r13.status_code == 401, f"status={r13.status_code}")

# ─────────────────────────────────────────────────────────────
# TEST 14: OTP forgot password flow
# ─────────────────────────────────────────────────────────────
print("\n===== TEST 14: OTP forgot password flow =====")
# Set DEBUG=true env for this test to get dev_otp
r14a = requests.post(f"{BASE}/api/v1/auth/forgot-password/request-otp", json={"email": email})
ok14a = r14a.status_code == 200
check("OTP request succeeds", ok14a, f"status={r14a.status_code}")

# Without DEBUG mode we can't get the OTP in a test — just check it returned 200
check("OTP flow response is well-formed", ok14a and "status" in r14a.json(), f"body={r14a.json()}")

# ─────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────
print("\n" + "="*50)
print("SUMMARY")
print("="*50)
passed = sum(1 for v in results.values() if v)
total = len(results)
for name, ok in results.items():
    print(f"  {'✅' if ok else '❌'} {name}")

print(f"\n{passed}/{total} tests passed")
if passed == total:
    print("\n🎉 ALL BACKEND TESTS PASSED")
    sys.exit(0)
else:
    print(f"\n⚠️  {total - passed} test(s) FAILED")
    sys.exit(1)
