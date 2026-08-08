from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Boolean
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from datetime import datetime
from app.database import Base

# -------------------------------------------------
# USER TABLE
# -------------------------------------------------
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=True, default="")  # Nullable for Google auth users
    google_id = Column(String, nullable=True, index=True)
    profile_photo = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    conversations = relationship("Conversation", back_populates="user", cascade="all, delete-orphan")


# -------------------------------------------------
# CONVERSATION TABLE
# -------------------------------------------------
class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(String, primary_key=True, index=True)  # UUID or Timestamp ID from frontend
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", back_populates="conversations")
    messages = relationship("ChatMessage", back_populates="conversation", cascade="all, delete-orphan")


# -------------------------------------------------
# CHAT MESSAGE TABLE
# -------------------------------------------------
class ChatMessage(Base):
    __tablename__ = "messages"

    id = Column(String, primary_key=True, index=True)
    conversation_id = Column(String, ForeignKey("conversations.id"), nullable=False, index=True)
    sender = Column(String, nullable=False)  # "user" or "bot"
    content = Column(Text, nullable=False)
    type = Column(String, default="text")  # "text", "image", "voice", "file"
    file_path = Column(String, nullable=True)
    file_name = Column(String, nullable=True)
    voice_duration = Column(String, nullable=True)
    image_url = Column(String, nullable=True)
    model_used = Column(String, nullable=True)
    like_status = Column(Integer, nullable=True)  # 1 = liked, -1 = disliked
    timestamp = Column(DateTime(timezone=True), server_default=func.now())

    conversation = relationship("Conversation", back_populates="messages")
    attachments = relationship("Attachment", back_populates="message", cascade="all, delete-orphan")


# -------------------------------------------------
# ATTACHMENT TABLE
# -------------------------------------------------
class Attachment(Base):
    __tablename__ = "attachments"

    id = Column(String, primary_key=True, index=True)
    message_id = Column(String, ForeignKey("messages.id"), nullable=False, index=True)
    file_name = Column(String, nullable=False)
    file_path = Column(String, nullable=False)
    file_type = Column(String, nullable=False)
    extracted_text = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    message = relationship("ChatMessage", back_populates="attachments")


# -------------------------------------------------
# OTP TOKEN TABLE (For Forgot Password)
# -------------------------------------------------
class OTPToken(Base):
    __tablename__ = "otp_tokens"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, nullable=False, index=True)
    otp_code = Column(String, nullable=False)
    expires_at = Column(DateTime, nullable=False)
    is_used = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)


# -------------------------------------------------
# LEGACY CHAT HISTORY TABLE (Backwards Compatibility)
# -------------------------------------------------
class ChatHistory(Base):
    __tablename__ = "chat_history"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=True)
    session_id = Column(String, nullable=True)
    user_message = Column(Text, nullable=False)
    bot_message = Column(Text, nullable=False)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
