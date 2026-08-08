import os
import uuid
import shutil
import logging
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.openapi.docs import get_swagger_ui_html
from pydantic import BaseModel
from typing import Optional

from app.ai_service import generate_text, select_best_model
from app.voice_service import text_to_speech, transcribe_audio
from app.database import Base, engine, SessionLocal
from app import models
from app.document_service import extract_text_from_document
from app.image_qa_service import extract_text_from_image
from app.image_generation_service import generate_image_from_api
from app.migrations import run_migrations
from app.auth_routes import router as auth_router
from app.conversation_routes import router as conversation_router
from dotenv import load_dotenv

load_dotenv()

# ============================================================
# LOGGING
# ============================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger("maveric_ai")

# ============================================================
# APP INIT & MIGRATIONS
# ============================================================

app = FastAPI(title="Maveric AI Backend", version="2.0.0")

# Run database migrations on startup
run_migrations()


def _build_allowed_origins() -> list[str]:
    """Build CORS allowlist from env vars, with safe local-dev defaults."""
    raw = os.getenv("ALLOWED_ORIGINS", "").strip()
    if raw:
        return [origin.strip() for origin in raw.split(",") if origin.strip()]

    frontend_url = os.getenv("FRONTEND_URL", "").strip()
    if frontend_url:
        return [frontend_url]

    # Local development defaults (credentials-safe; no wildcard)
    return [
        "http://localhost:8080",
        "http://localhost:3000",
        "http://localhost:5000",
        "http://localhost:8000",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5000",
        "http://127.0.0.1:8000",
    ]


# CORS — restrict in production via FRONTEND_URL or ALLOWED_ORIGINS
_allowed_origins = _build_allowed_origins()
_debug_mode = os.getenv("DEBUG", "false").lower() == "true"

_cors_kwargs = dict(
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

if _debug_mode and not os.getenv("ALLOWED_ORIGINS") and not os.getenv("FRONTEND_URL"):
    # Local dev: allow any localhost port (Flutter Web uses dynamic ports)
    _cors_kwargs["allow_origin_regex"] = r"http://(localhost|127\.0\.0\.1)(:\d+)?"
else:
    _cors_kwargs["allow_origins"] = _allowed_origins

app.add_middleware(CORSMiddleware, **_cors_kwargs)

# Include Auth & Conversation Routers
app.include_router(auth_router)
app.include_router(conversation_router)

# ============================================================
# UPLOAD DIRECTORIES
# ============================================================

UPLOAD_DIRS = {
    "attachments": "app/uploaded_files/attachments",
    "documents": "app/uploaded_files/documents",
    "images": "app/uploaded_files/images",
    "voice": "app/uploaded_files/voice",
}
for d in UPLOAD_DIRS.values():
    os.makedirs(d, exist_ok=True)


def _safe_filename(filename: str) -> str:
    """Sanitize filename to prevent path traversal attacks."""
    safe = Path(filename).name  # strips directory components
    # Replace any remaining dangerous characters
    safe = "".join(c for c in safe if c.isalnum() or c in (".", "_", "-"))
    if not safe:
        safe = str(uuid.uuid4())
    return safe


# ============================================================
# REQUEST MODELS
# ============================================================

class ChatRequest(BaseModel):
    message: str
    user_id: Optional[int] = None
    session_id: Optional[str] = None
    file_text: Optional[str] = None
    file_name: Optional[str] = None
    file_path: Optional[str] = None
    conversation_id: Optional[str] = None


# ============================================================
# HOME
# ============================================================

@app.get("/")
def home():
    active_model = select_best_model()
    return {
        "status": "Maveric AI Backend Running Successfully",
        "version": "2.0.0",
        "active_ai_model": active_model
    }


@app.get("/docs", include_in_schema=False)
async def custom_swagger_ui_html():
    return get_swagger_ui_html(
        openapi_url=app.openapi_url,
        title=f"{app.title} - Swagger UI",
        oauth2_redirect_url=app.swagger_ui_oauth2_redirect_url,
        swagger_js_url="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.9.0/swagger-ui-bundle.min.js",
        swagger_css_url="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.9.0/swagger-ui.min.css",
    )


# ============================================================
# CHAT (UNIFIED WITH ATTACHMENT CONTEXT & DYNAMIC AI)
# ============================================================

@app.post("/chat")
def chat(request: ChatRequest):
    db = SessionLocal()
    try:
        full_prompt = request.message

        image_base64 = None
        is_image = False
        if request.file_path and os.path.exists(request.file_path):
            if request.file_path.lower().endswith(('.png', '.jpg', '.jpeg', '.webp')):
                is_image = True
                import base64
                with open(request.file_path, "rb") as f:
                    image_base64 = base64.b64encode(f.read()).decode("utf-8")

        # Inject attachment text if provided AND it's not an image being sent to the vision model
        if request.file_text and request.file_text.strip() and not is_image:
            file_label = request.file_name or "Attached File"
            full_prompt = (
                f"Content from attached file ({file_label}):\n"
                f"--- BEGIN ATTACHMENT ---\n"
                f"{request.file_text.strip()}\n"
                f"--- END ATTACHMENT ---\n\n"
                f"User Question:\n{request.message}"
            )

        response_text, model_used = generate_text(full_prompt, image_base64=image_base64)

        logger.info("Chat: user_id=%s model=%s", request.user_id, model_used)

        return {
            "reply": response_text,
            "model_used": model_used,
            "status": "SUCCESS"
        }

    except Exception as e:
        db.rollback()
        logger.error("Chat error: %s", e, exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        db.close()


@app.post("/chat/stream")
def chat_stream(request: ChatRequest):
    full_prompt = request.message
    if request.file_text and request.file_text.strip():
        file_label = request.file_name or "Attached File"
        full_prompt = (
            f"Content from attached file ({file_label}):\n"
            f"--- BEGIN ATTACHMENT ---\n"
            f"{request.file_text.strip()}\n"
            f"--- END ATTACHMENT ---\n\n"
            f"User Question:\n{request.message}"
        )

    image_base64 = None
    if request.file_path and os.path.exists(request.file_path):
        if request.file_path.lower().endswith(('.png', '.jpg', '.jpeg', '.webp')):
            import base64
            with open(request.file_path, "rb") as f:
                image_base64 = base64.b64encode(f.read()).decode("utf-8")

    def event_generator():
        response_text, _ = generate_text(full_prompt, image_base64=image_base64)
        words = response_text.split(" ")
        for i, word in enumerate(words):
            chunk = word + (" " if i < len(words) - 1 else "")
            yield chunk

    return StreamingResponse(event_generator(), media_type="text/plain")


# ============================================================
# MULTI-FORMAT FILE ATTACHMENT EXTRACTION
# ============================================================

@app.post("/upload-attachment")
def upload_attachment(file: UploadFile = File(...)):
    safe_name = _safe_filename(file.filename or "file")
    path = f"{UPLOAD_DIRS['attachments']}/{safe_name}"

    with open(path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    extracted_text = extract_text_from_document(path)
    logger.info("Attachment uploaded: %s (%d chars extracted)", safe_name, len(extracted_text or ""))

    return {
        "status": "SUCCESS",
        "file_name": safe_name,
        "file_path": path,
        "extracted_text": extracted_text
    }


# ============================================================
# IMAGE QUERY (Stateless: image path passed per-request)
# ============================================================

@app.post("/upload-image-query")
def upload_image_query(file: UploadFile = File(...)):
    """Upload an image and get its text/description extracted (stateless)."""
    safe_name = _safe_filename(file.filename or "image.jpg")
    path = f"{UPLOAD_DIRS['images']}/{safe_name}"

    with open(path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    image_text = extract_text_from_image(path)
    return {
        "status": "SUCCESS",
        "file_name": safe_name,
        "file_path": path,
        "extracted_text": image_text
    }


# ============================================================
# IMAGE GENERATION
# ============================================================

@app.post("/generate-image")
def generate_image(request: ChatRequest):
    filename = f"generated_{uuid.uuid4().hex[:8]}.png"
    output_path = f"{UPLOAD_DIRS['images']}/{filename}"
    status_res = generate_image_from_api(request.message, output_path)

    if status_res != "SUCCESS":
        raise HTTPException(status_code=500, detail="Image generation failed")

    image_url = f"/generated-image/{filename}"

    # Return a relative URL — the client will prepend its own baseUrl.
    # This avoids the hardcoded localhost:8000 that breaks on Android emulator.
    return {
        "status": "SUCCESS",
        "image_path": output_path,
        "image_url": image_url
    }


@app.get("/generated-image/{filename}")
def get_generated_image_by_name(filename: str):
    """Serve generated images by filename — works from any client (Android/Web/Desktop)."""
    safe = _safe_filename(filename)
    resolved = (Path(UPLOAD_DIRS['images']) / safe).resolve()
    allowed_base = Path(UPLOAD_DIRS['images']).resolve()
    if not str(resolved).startswith(str(allowed_base)):
        raise HTTPException(status_code=403, detail="Access denied")
    if not resolved.exists():
        raise HTTPException(status_code=404, detail="Image not found")
    return FileResponse(str(resolved), media_type="image/png")


@app.get("/generated-image")
def get_generated_image(path: Optional[str] = None):
    """Legacy query-param image endpoint — kept for backward compatibility."""
    if not path:
        raise HTTPException(status_code=400, detail="path parameter required")
    resolved = Path(path).resolve()
    allowed_base = Path(UPLOAD_DIRS['images']).resolve()
    if not str(resolved).startswith(str(allowed_base)):
        raise HTTPException(status_code=403, detail="Access denied")
    if not resolved.exists():
        raise HTTPException(status_code=404, detail="Image not found")
    return FileResponse(str(resolved), media_type="image/png")


# ============================================================
# VOICE (TTS & STT)
# ============================================================

@app.post("/speak")
def speak(request: ChatRequest):
    filename = f"{UPLOAD_DIRS['voice']}/tts_{uuid.uuid4().hex[:8]}.wav"
    text_to_speech(request.message, filename)
    return FileResponse(filename, media_type="audio/wav")


@app.post("/transcribe")
def transcribe(file: UploadFile = File(...)):
    safe_name = _safe_filename(file.filename or "audio.wav")
    path = f"{UPLOAD_DIRS['voice']}/{safe_name}"

    with open(path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    transcription = transcribe_audio(path)
    logger.info("Transcription complete: %d chars", len(transcription or ""))

    return {
        "status": "SUCCESS",
        "transcription": transcription,
        "file_path": path
    }


# NOTE: Legacy /register, /login, /google-auth, /upload-document,
# /ask-from-document, /upload-image, /ask-from-image endpoints have been
# REMOVED. Use the versioned equivalents:
#   POST /api/v1/auth/register
#   POST /api/v1/auth/login
#   POST /api/v1/auth/google
#   POST /upload-attachment  (stateless, handles all file types)
#   POST /upload-image-query (stateless image OCR)
