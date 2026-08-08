# 🔥 Firebase Setup Guide — Maveric AI

> Follow these steps **exactly once** to enable Google Sign-In.  
> When done, Google login will work on any real Android device.

---

## Step 1 — Create a Firebase Project

1. Go to **https://console.firebase.google.com**
2. Click **"Add project"**
3. Name it: `maveric-ai` (or anything you like)
4. Disable Google Analytics (optional)
5. Click **"Create project"**

---

## Step 2 — Register Your Android App

1. In the Firebase console, click **"Add app"** → **Android icon**
2. Fill in:
   - **Android package name**: `com.example.ai_chatbot_frontend_fixed`
     > ⚠️ Must match exactly what's in `android/app/build.gradle.kts` → `applicationId`
   - **App nickname**: Maveric AI (optional)
   - **Debug signing certificate SHA-1**: (get from Step 3)
3. Click **"Register app"**

---

## Step 3 — Get SHA-1 and SHA-256 Fingerprints

Run this command in PowerShell (from your project root):

```powershell
cd e:\Projects\ai_chatbot_project\frontend\ai_chatbot_frontend_fixed
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android 2>&1 | Select-String -Pattern "SHA"
```

You will see output like:
```
SHA1:   AA:BB:CC:DD:...
SHA256: 11:22:33:44:...
```

Copy **both** values — paste them in the Firebase console under:
- `Project Settings → Your apps → SHA certificate fingerprints → Add fingerprint`

---

## Step 4 — Download google-services.json

1. After registering the app, click **"Download google-services.json"**
2. Copy the file to:
   ```
   e:\Projects\ai_chatbot_project\frontend\ai_chatbot_frontend_fixed\android\app\google-services.json
   ```
   > This replaces the placeholder file that is currently there.

---

## Step 5 — Enable Google Sign-In in Firebase

1. In Firebase console → **Authentication** → **Sign-in method**
2. Click **"Google"**
3. Toggle **Enable** → ON
4. Set a **Project support email**
5. Click **"Save"**

---

## Step 6 — Add SHA fingerprints to Firebase

1. Go to Firebase console → **Project Settings** (gear icon)
2. Scroll down to **Your apps** → select your Android app
3. Click **"Add fingerprint"**
4. Add both **SHA-1** and **SHA-256** from Step 3
5. Click **"Save"**

---

## Step 7 — Get the Web Client ID

1. In Firebase console → **Authentication** → **Sign-in method** → **Google** → **Web SDK configuration**
2. Copy the **Web client ID** (looks like: `1234567890-abc123.apps.googleusercontent.com`)
3. You may need to add this to `android/app/res/values/strings.xml`:
   ```xml
   <string name="default_web_client_id">YOUR_WEB_CLIENT_ID_HERE</string>
   ```
   > The `google-services.json` plugin generates this automatically if you downloaded the correct file.

---

## Step 8 — Build and Test

```powershell
# Run on Android emulator (make sure it's running)
cd e:\Projects\ai_chatbot_project\frontend\ai_chatbot_frontend_fixed
flutter run

# Or build an APK for real device
flutter build apk --debug
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `PlatformException: sign_in_failed` | SHA-1 not added to Firebase |
| `FirebaseException: no-app` | `google-services.json` is the placeholder, not real |
| `ApiException: 10` | Web client ID mismatch — check strings.xml |
| Google sign-in cancelled immediately | Firebase project not fully configured |
| Works on emulator but not real device | Add SHA-1 of your **release** keystore too |

---

## Windows Development Note

Google Sign-In uses Firebase Auth which **does not support Windows desktop**.  
On Windows, the app shows a friendly message: "Google Sign-In not supported on Windows. Use email/password."

Email/password and guest login work on all platforms including Windows.

---

## Backend Note

The backend `POST /api/v1/auth/google` endpoint is already fully implemented.  
Once the user signs in with Google, the app automatically:
1. Creates or links their account on your backend
2. Stores JWT tokens via `SessionManager`
3. Loads their conversation history

No additional backend changes are needed.
