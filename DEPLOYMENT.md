# Maveric AI — Deployment Guide

This document describes how to run Maveric AI locally and deploy it for **₹0** using free tiers.

---

## Architecture Overview

### Local (current)

```
Flutter Web / Android / Desktop
        ↓
http://localhost:8000  (FastAPI)
        ↓
http://localhost:11434  (Ollama — qwen3:latest, qwen2.5vl:latest)
        ↓
SQLite (backend/chat.db) + local filesystem uploads
```

### Production (target)

```
Flutter Web (static hosting — GitHub Pages / Cloudflare Pages / Netlify)
        ↓
https://<backend>.onrender.com  (FastAPI on Render free tier)
        ↓
https://ollama.com  (Ollama Cloud free tier + API key)
        ↓
SQLite on ephemeral disk (first deploy) OR external Postgres (optional)
```

---

## 1. Run Backend Locally

From the project root:

```powershell
cd E:\Projects\ai_chatbot_project\backend
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
# Edit .env with your local values (JWT_SECRET, SMTP, etc.)
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Verify: open http://127.0.0.1:8000 — you should see JSON status with `"status": "Maveric AI Backend Running Successfully"`.

**Start command (production-style):**

```bash
uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

(`$PORT` is set automatically on Render.)

---

## 2. Run Frontend Locally

```powershell
cd E:\Projects\ai_chatbot_project\frontend\ai_chatbot_frontend_fixed
flutter pub get
flutter run -d chrome
```

Flutter Web talks to `http://localhost:8000` by default (see `lib/api_service.dart`).

To point at a different backend:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

---

## 3. Required Environment Variables

Copy `backend/.env.example` → `backend/.env` and fill in values.

| Variable | Required | Local default | Production notes |
|----------|----------|---------------|-------------------|
| `JWT_SECRET` | **Yes (prod)** | insecure default | Generate a long random string |
| `DATABASE_URL` | No | `sqlite:///./chat.db` | Optional: Neon/Supabase Postgres URL |
| `OLLAMA_BASE_URL` | No | `http://localhost:11434` | `https://ollama.com` for cloud |
| `OLLAMA_API_KEY` | Cloud only | empty | From https://ollama.com/settings/keys |
| `TEXT_MODEL` | No | auto-detect | e.g. cloud text model from Ollama catalog |
| `VISION_MODEL` | No | auto-detect | e.g. cloud vision model from Ollama catalog |
| `TEXT_TIMEOUT` | No | `60` | Seconds for text chat |
| `VISION_TIMEOUT` | No | `300` | Seconds for vision chat |
| `FRONTEND_URL` | Prod | empty | Your deployed Flutter Web URL |
| `ALLOWED_ORIGINS` | Prod alt | empty | Comma-separated CORS origins |
| `SMTP_HOST` | OTP email | empty | Gmail SMTP for forgot-password |
| `SMTP_PORT` | No | `587` | |
| `SMTP_USERNAME` | OTP email | empty | |
| `SMTP_PASSWORD` | OTP email | empty | Gmail app password |
| `FROM_EMAIL` | OTP email | empty | |
| `DEBUG` | No | `false` | `true` enables permissive localhost CORS |
| `TESSERACT_CMD` | No | auto-detect | Path to tesseract binary |

**Never commit `backend/.env`.** Only commit `backend/.env.example`.

---

## 4. Deploy Backend to Render (Free Tier)

### Prerequisites

- GitHub repo with this project pushed (without `.env`, `*.db`, or `uploaded_files/`)
- Render account (free, no credit card required)
- Ollama Cloud API key (free tier at https://ollama.com)

### Option A — Dashboard (manual)

1. Go to https://dashboard.render.com → **New → Web Service**
2. Connect your GitHub repository
3. Configure:

| Setting | Value |
|---------|-------|
| **Name** | `maveric-ai-backend` |
| **Root Directory** | `backend` |
| **Runtime** | Python 3 |
| **Build Command** | `pip install -r requirements.txt` |
| **Start Command** | `uvicorn app.main:app --host 0.0.0.0 --port $PORT` |
| **Plan** | Free |

4. Add environment variables (see section 7 below)
5. Click **Create Web Service**
6. Note your URL: `https://maveric-ai-backend.onrender.com` (example)

### Option B — Blueprint

A `render.yaml` is included at the repo root. Connect the repo in Render and apply the blueprint, then set secret env vars in the dashboard.

---

## 5. Render Build Command

```
pip install -r requirements.txt
```

Run from the `backend/` root directory.

---

## 6. Render Start Command

```
uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

FastAPI entry point: `app/main.py` → `app` object in `app.main:app`.

---

## 7. Render Environment Variables

Set these in the Render dashboard:

| Key | Example / notes |
|-----|-----------------|
| `JWT_SECRET` | Long random string (Render can auto-generate) |
| `OLLAMA_BASE_URL` | `https://ollama.com` |
| `OLLAMA_API_KEY` | Your Ollama Cloud API key |
| `TEXT_MODEL` | Cloud-compatible text model (see Ollama model catalog) |
| `VISION_MODEL` | Cloud-compatible vision model |
| `FRONTEND_URL` | `https://your-username.github.io/maveric-ai` (set after frontend deploy) |
| `DEBUG` | `false` |
| `SMTP_HOST` | `smtp.gmail.com` (optional, for forgot-password) |
| `SMTP_PORT` | `587` |
| `SMTP_USERNAME` | your email |
| `SMTP_PASSWORD` | Gmail app password |
| `FROM_EMAIL` | your email |

---

## 8. Build Flutter Web

```powershell
cd E:\Projects\ai_chatbot_project\frontend\ai_chatbot_frontend_fixed
flutter pub get
flutter analyze
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-BACKEND.onrender.com
```

Output: `build/web/`

---

## 9. Deploy Flutter Web (Free Static Hosting)

Any static host works. Examples:

### GitHub Pages

1. Push `build/web/` contents to a `gh-pages` branch or use GitHub Actions
2. Enable Pages in repo Settings → Pages
3. Set `FRONTEND_URL` on Render to your Pages URL
4. Rebuild if CORS origin changes

### Cloudflare Pages

1. Connect repo or upload `build/web/`
2. Build command: `flutter build web --release --dart-define=API_BASE_URL=...`
3. Output directory: `build/web`

### Netlify

1. Drag-and-drop `build/web/` folder, or connect repo with same build settings

---

## 10. Configure Production API URL

Single point of configuration: **`lib/api_service.dart`**

- **Local:** no flag needed — defaults to `http://localhost:8000` on Web
- **Production build:**

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-BACKEND.onrender.com
```

All API calls (`/chat`, `/upload-attachment`, `/transcribe`, auth routes, etc.) use `ApiService.baseUrl`.

---

## 11. Post-Deploy Testing Checklist

After both backend and frontend are live:

- [ ] **Login** — register/login at production frontend URL
- [ ] **Text chat** — send a message, confirm qwen/text model reply
- [ ] **Image upload** — attach PNG/JPG, confirm thumbnail preview (Web)
- [ ] **Image vision** — ask about attached image (may take up to 300s)
- [ ] **Voice transcription** — record voice note, confirm transcription
- [ ] **Conversation history** — refresh page, confirm chats persist
- [ ] **Generated image** — request image generation, confirm display
- [ ] **Full-screen image** — tap image to open viewer

**Cold start:** Render free tier sleeps after 15 min idle. First request may take 30–60 seconds.

---

## 12. Known Free-Tier Limitations

| Limitation | Impact |
|------------|--------|
| **Render spin-down** | 15 min idle → 30–60s cold start |
| **Ephemeral filesystem** | SQLite DB + uploaded files lost on redeploy/restart |
| **512 MB RAM** | Large vision models via cloud API (not local RAM) |
| **No Tesseract on Render** | OCR falls back to PIL metadata (no text extraction) |
| **No ffmpeg on Render** | Voice `.m4a` conversion may fail; use `.wav` or install ffmpeg in build |
| **Ollama Cloud free quota** | Light usage; GPU-time limits reset every 5h / 7d |
| **qwen3:latest / qwen2.5vl:latest** | Local Ollama tags; cloud uses different model names — set `TEXT_MODEL` / `VISION_MODEL` |
| **Render Postgres free** | Expires after 30 days — use Neon (free) for durable DB if needed |
| **Google Sign-In on Web** | Requires Firebase Web app config (separate from Android) |
| **CORS** | Must set `FRONTEND_URL` to exact deployed frontend origin |

### Data affected by ephemeral storage (SQLite + local files)

| Data | Storage | Lost on redeploy? |
|------|---------|-------------------|
| Users / auth | SQLite | Yes (unless external DB) |
| Conversations | SQLite | Yes |
| Messages | SQLite | Yes |
| Attachments metadata | SQLite | Yes |
| Uploaded images/voice/docs | `app/uploaded_files/` | Yes |
| Generated images | `app/uploaded_files/images/` | Yes |
| JWT sessions | Client-side | No (but users lost if DB wiped) |

For a durable free setup later: **Neon Postgres** (free) + keep uploads on ephemeral disk (acceptable for demo) or add free object storage later.

---

## Ollama: Local vs Cloud

### Local (unchanged)

```env
OLLAMA_BASE_URL=http://localhost:11434
TEXT_MODEL=
VISION_MODEL=
```

Uses installed models: `qwen3:latest`, `qwen2.5vl:latest`.

### Cloud (production)

```env
OLLAMA_BASE_URL=https://ollama.com
OLLAMA_API_KEY=your_key_from_ollama_com_settings
TEXT_MODEL=<cloud text model from https://ollama.com/search>
VISION_MODEL=<cloud vision model from catalog>
```

The backend calls Ollama's native `/api/generate` endpoint with optional `Authorization: Bearer` header. Vision requests include base64 images in the `images` array (same as local).

**Important:** Cloud model names differ from local tags. List available models:

```bash
curl https://ollama.com/api/tags -H "Authorization: Bearer YOUR_API_KEY"
```

Pick a text model and a vision-capable model from the results.

---

## API Routes Reference

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | Health / status |
| POST | `/chat` | Text + vision chat |
| POST | `/chat/stream` | Streaming chat |
| POST | `/upload-attachment` | File upload + OCR/extraction |
| POST | `/upload-image-query` | Image OCR |
| POST | `/generate-image` | AI image generation |
| GET | `/generated-image/{filename}` | Serve generated image |
| POST | `/transcribe` | Voice → text |
| POST | `/speak` | Text → speech |
| POST | `/api/v1/auth/register` | Register |
| POST | `/api/v1/auth/login` | Login |
| POST | `/api/v1/auth/google` | Google auth |
| GET | `/api/v1/conversations` | List conversations |
| POST | `/api/v1/conversations` | Create conversation |
| GET | `/api/v1/conversations/{id}` | Get conversation + messages |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| CORS error in browser | Set `FRONTEND_URL` on Render to exact frontend origin (scheme + host + port) |
| AI returns "Service Unavailable" | Check `OLLAMA_BASE_URL`, `OLLAMA_API_KEY`, model names |
| 401 on conversations | Log in again; check `JWT_SECRET` is set and consistent |
| Upload works but vision fails | Confirm `VISION_MODEL` supports images on Ollama Cloud |
| Cold start timeout | Retry after 60s or upgrade Render plan |
| Flutter Web can't reach API | Rebuild with correct `--dart-define=API_BASE_URL=...` |

---

## Files Changed for Deployment Prep

- `backend/.env.example` — env var template
- `backend/app/ai_service.py` — configurable Ollama URL/models
- `backend/app/main.py` — CORS via `FRONTEND_URL` / `DEBUG`
- `backend/app/database.py` — PostgreSQL-compatible connect args
- `backend/requirements.txt` — added `python-dotenv`, voice deps
- `frontend/.../lib/api_service.dart` — `API_BASE_URL` dart-define
- `render.yaml` — Render blueprint
- `.gitignore` — secrets, DB, uploads, build artifacts
- `DEPLOYMENT.md` — this file

**Not changed:** Android/Gradle, vision logic, voice logic, image attachment Web fixes.
