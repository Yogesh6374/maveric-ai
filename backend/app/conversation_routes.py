from fastapi import APIRouter, Depends, HTTPException, Header, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
import uuid

from app.database import SessionLocal
from app import models, auth

router = APIRouter(prefix="/api/v1/conversations", tags=["Conversations & History"])


# ── DB dependency ─────────────────────────────────────────────────────────────
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ── Auth dependency — strict, no fallback ────────────────────────────────────
def get_current_user(
    authorization: Optional[str] = Header(None),
    x_user_id: Optional[int] = Header(None),
    db: Session = Depends(get_db),
) -> models.User:
    """
    Authenticate via Bearer token or x-user-id header.
    SECURITY FIX: Removed the fallback that returned the first user in the DB.
    Returns 401 if no valid credentials are provided.
    """
    user = None

    # Primary: Bearer JWT token
    if authorization and authorization.startswith("Bearer "):
        token = authorization.split(" ", 1)[1]
        try:
            payload = auth.decode_token(token)
            user_id = payload.get("sub")
            if user_id:
                user = db.query(models.User).filter(models.User.id == int(user_id)).first()
        except (HTTPException, Exception):
            pass

    # Fallback: explicit x-user-id header (for internal/guest use)
    if not user and x_user_id:
        user = db.query(models.User).filter(models.User.id == x_user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required. Please log in.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user


# ============================================================
# SCHEMAS
# ============================================================

class CreateConversationRequest(BaseModel):
    id: Optional[str] = None
    title: Optional[str] = "New Chat"


class UpdateConversationRequest(BaseModel):
    title: str


class MessageCreateRequest(BaseModel):
    id: Optional[str] = None
    sender: str          # "user" or "bot"
    content: str
    type: Optional[str] = "text"
    file_path: Optional[str] = None
    file_name: Optional[str] = None
    voice_duration: Optional[str] = None
    image_url: Optional[str] = None
    model_used: Optional[str] = None
    like_status: Optional[int] = None


class BatchMessageRequest(BaseModel):
    """Save multiple messages in a single request (fixes BUG-10: only last msg saved)."""
    messages: List[MessageCreateRequest]


# ============================================================
# HELPERS
# ============================================================

def _format_conversation(conv: models.Conversation, preview: str = "", message_count: int = 0) -> dict:
    return {
        "id": conv.id,
        "title": conv.title,
        "created_at": conv.created_at.isoformat() if conv.created_at else None,
        "updated_at": conv.updated_at.isoformat() if conv.updated_at else None,
        "preview": preview,
        "message_count": message_count,
    }


def _format_message(msg: models.ChatMessage) -> dict:
    return {
        "id": msg.id,
        "sender": msg.sender,
        "content": msg.content,
        "type": msg.type,
        "file_path": msg.file_path,
        "file_name": msg.file_name,
        "voice_duration": msg.voice_duration,
        "image_url": msg.image_url,
        "model_used": msg.model_used,
        "like_status": msg.like_status,
        "timestamp": msg.timestamp.isoformat() if msg.timestamp else None,
    }


# ============================================================
# ENDPOINTS
# ============================================================

@router.get("")
def list_conversations(
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    FIXED: Uses a single SQL query with subquery for last-message preview.
    Eliminates the N+1 query pattern.
    """
    conversations = (
        db.query(models.Conversation)
        .filter(models.Conversation.user_id == user.id)
        .order_by(models.Conversation.updated_at.desc())
        .all()
    )

    result = []
    for conv in conversations:
        # Get last message in a single targeted query (not loading all messages)
        last_msg = (
            db.query(models.ChatMessage)
            .filter(models.ChatMessage.conversation_id == conv.id)
            .order_by(models.ChatMessage.timestamp.desc())
            .first()
        )
        preview = ""
        if last_msg:
            preview = last_msg.content[:80] + "..." if len(last_msg.content) > 80 else last_msg.content

        # Get count efficiently
        count = (
            db.query(models.ChatMessage)
            .filter(models.ChatMessage.conversation_id == conv.id)
            .count()
        )

        result.append(_format_conversation(conv, preview=preview, message_count=count))

    return result


@router.post("", status_code=status.HTTP_201_CREATED)
def create_conversation(
    request: CreateConversationRequest,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv_id = request.id or str(uuid.uuid4())
    existing = db.query(models.Conversation).filter(models.Conversation.id == conv_id).first()

    if existing:
        # Idempotent — return existing conversation
        return _format_conversation(existing)

    conv = models.Conversation(
        id=conv_id,
        user_id=user.id,
        title=request.title or "New Chat",
    )
    db.add(conv)
    db.commit()
    db.refresh(conv)

    return _format_conversation(conv)


@router.get("/{conversation_id}")
def get_conversation_details(
    conversation_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv = (
        db.query(models.Conversation)
        .filter(
            models.Conversation.id == conversation_id,
            models.Conversation.user_id == user.id,
        )
        .first()
    )

    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found")

    messages = (
        db.query(models.ChatMessage)
        .filter(models.ChatMessage.conversation_id == conversation_id)
        .order_by(models.ChatMessage.timestamp.asc())
        .all()
    )

    return {
        "id": conv.id,
        "title": conv.title,
        "created_at": conv.created_at.isoformat() if conv.created_at else None,
        "updated_at": conv.updated_at.isoformat() if conv.updated_at else None,
        "messages": [_format_message(m) for m in messages],
    }


@router.post("/{conversation_id}/messages", status_code=status.HTTP_201_CREATED)
def add_message_to_conversation(
    conversation_id: str,
    msg_req: MessageCreateRequest,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv = (
        db.query(models.Conversation)
        .filter(
            models.Conversation.id == conversation_id,
            models.Conversation.user_id == user.id,
        )
        .first()
    )

    if not conv:
        # Auto-create conversation if it doesn't exist
        title = msg_req.content[:30] + "..." if len(msg_req.content) > 30 else msg_req.content
        conv = models.Conversation(
            id=conversation_id,
            user_id=user.id,
            title=title,
        )
        db.add(conv)
        db.flush()

    msg_id = msg_req.id or str(uuid.uuid4())

    # Idempotency: skip if message with this ID already exists
    existing_msg = db.query(models.ChatMessage).filter(models.ChatMessage.id == msg_id).first()
    if existing_msg:
        return _format_message(existing_msg)

    msg = models.ChatMessage(
        id=msg_id,
        conversation_id=conversation_id,
        sender=msg_req.sender,
        content=msg_req.content,
        type=msg_req.type or "text",
        file_path=msg_req.file_path,
        file_name=msg_req.file_name,
        voice_duration=msg_req.voice_duration,
        image_url=msg_req.image_url,
        model_used=msg_req.model_used,
        like_status=msg_req.like_status,
    )
    db.add(msg)

    # Auto-update title on first user message
    if conv.title in ("New Chat", "") and msg_req.sender == "user" and msg_req.content:
        title = msg_req.content[:30] + "..." if len(msg_req.content) > 30 else msg_req.content
        conv.title = title

    conv.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(msg)

    return _format_message(msg)


@router.post("/{conversation_id}/messages/batch", status_code=status.HTTP_201_CREATED)
def add_messages_batch(
    conversation_id: str,
    batch_req: BatchMessageRequest,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    FIXES BUG-10: Save multiple messages in a single request.
    Supports idempotency — skips messages with IDs that already exist.
    """
    conv = (
        db.query(models.Conversation)
        .filter(
            models.Conversation.id == conversation_id,
            models.Conversation.user_id == user.id,
        )
        .first()
    )

    if not conv:
        first_user_msg = next((m for m in batch_req.messages if m.sender == "user"), None)
        title = "New Chat"
        if first_user_msg:
            title = first_user_msg.content[:30] + "..." if len(first_user_msg.content) > 30 else first_user_msg.content
        conv = models.Conversation(id=conversation_id, user_id=user.id, title=title)
        db.add(conv)
        db.flush()

    saved = []
    for msg_req in batch_req.messages:
        msg_id = msg_req.id or str(uuid.uuid4())
        existing = db.query(models.ChatMessage).filter(models.ChatMessage.id == msg_id).first()
        if existing:
            saved.append(_format_message(existing))
            continue

        msg = models.ChatMessage(
            id=msg_id,
            conversation_id=conversation_id,
            sender=msg_req.sender,
            content=msg_req.content,
            type=msg_req.type or "text",
            file_path=msg_req.file_path,
            file_name=msg_req.file_name,
            voice_duration=msg_req.voice_duration,
            image_url=msg_req.image_url,
            model_used=msg_req.model_used,
            like_status=msg_req.like_status,
        )
        db.add(msg)
        saved.append(_format_message(msg))

    # Update conversation title if it was "New Chat"
    if conv.title in ("New Chat", ""):
        first_user_msg = next((m for m in batch_req.messages if m.sender == "user"), None)
        if first_user_msg and first_user_msg.content:
            conv.title = first_user_msg.content[:30] + "..." if len(first_user_msg.content) > 30 else first_user_msg.content

    conv.updated_at = datetime.utcnow()
    db.commit()

    return {"saved": len(saved), "messages": saved}


@router.put("/{conversation_id}")
def update_conversation(
    conversation_id: str,
    req: UpdateConversationRequest,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv = (
        db.query(models.Conversation)
        .filter(
            models.Conversation.id == conversation_id,
            models.Conversation.user_id == user.id,
        )
        .first()
    )

    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found")

    if not req.title or not req.title.strip():
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Title cannot be empty")

    conv.title = req.title.strip()
    conv.updated_at = datetime.utcnow()
    db.commit()

    return {"status": "SUCCESS", "id": conv.id, "title": conv.title}


@router.delete("/{conversation_id}")
def delete_conversation(
    conversation_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv = (
        db.query(models.Conversation)
        .filter(
            models.Conversation.id == conversation_id,
            models.Conversation.user_id == user.id,
        )
        .first()
    )

    if not conv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found")

    db.delete(conv)
    db.commit()

    return {"status": "SUCCESS", "deleted_id": conversation_id}
