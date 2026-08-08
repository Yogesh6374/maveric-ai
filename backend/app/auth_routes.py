import os
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime, timedelta

from app.database import SessionLocal
from app import models, auth

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])

# ── simple in-memory OTP rate limiter (per email, per process) ────────────────
_otp_attempts: dict[str, list[datetime]] = {}
_OTP_MAX_PER_HOUR = 5
_DEBUG = os.getenv("DEBUG", "false").lower() == "true"


def _check_otp_rate_limit(email: str) -> None:
    now = datetime.utcnow()
    window = now - timedelta(hours=1)
    attempts = [t for t in _otp_attempts.get(email, []) if t > window]
    if len(attempts) >= _OTP_MAX_PER_HOUR:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many OTP requests. Please wait before trying again.",
        )
    _otp_attempts[email] = attempts + [now]


# ── DB dependency ─────────────────────────────────────────────────────────────
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ============================================================
# SCHEMAS
# ============================================================

class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str
    session_id: Optional[str] = None


class LoginRequest(BaseModel):
    email: str
    password: str
    session_id: Optional[str] = None


class GoogleAuthRequest(BaseModel):
    google_id: str
    email: EmailStr
    name: str
    profile_photo: Optional[str] = None
    session_id: Optional[str] = None


class ForgotPasswordOTPRequest(BaseModel):
    email: str


class ForgotPasswordVerifyOTPRequest(BaseModel):
    email: str
    otp: str


class ResetPasswordRequest(BaseModel):
    reset_token: str   # signed JWT issued after OTP verify
    new_password: str


class RefreshTokenRequest(BaseModel):
    refresh_token: str


# ============================================================
# HELPERS
# ============================================================

def _build_auth_response(user: models.User) -> dict:
    access_token = auth.create_access_token({"sub": str(user.id), "email": user.email})
    refresh_token = auth.create_refresh_token({"sub": str(user.id), "email": user.email})
    return {
        "user_id": user.id,
        "name": user.name,
        "email": user.email,
        "google_id": user.google_id,
        "profile_photo": user.profile_photo,
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


# ============================================================
# ENDPOINTS
# ============================================================

@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(request: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(models.User).filter(models.User.email == request.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    if len(request.password) < 6:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Password must be at least 6 characters",
        )

    user = models.User(
        name=request.name.strip(),
        email=request.email,
        password_hash=auth.hash_password(request.password),
        google_id=None,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return _build_auth_response(user)


@router.post("/login")
def login(request: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == request.email).first()
    if not user or not user.password_hash or not auth.verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    # Transparently upgrade legacy PBKDF2 hashes to bcrypt on first login
    if auth.needs_rehash(user.password_hash):
        user.password_hash = auth.hash_password(request.password)
        db.commit()

    return _build_auth_response(user)



@router.post("/google")
def google_auth(request: GoogleAuthRequest, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == request.email).first()

    if user:
        if not user.google_id:
            user.google_id = request.google_id
        if request.profile_photo:
            user.profile_photo = request.profile_photo
        db.commit()
        db.refresh(user)
    else:
        user = models.User(
            name=request.name.strip(),
            email=request.email,
            password_hash="",
            google_id=request.google_id,
            profile_photo=request.profile_photo,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    return _build_auth_response(user)


@router.post("/forgot-password/request-otp")
def request_otp(request: ForgotPasswordOTPRequest, db: Session = Depends(get_db)):
    # Rate limiting
    _check_otp_rate_limit(request.email)

    user = db.query(models.User).filter(models.User.email == request.email).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No account found with this email address",
        )

    otp_code = auth.generate_otp(6)
    expires_at = datetime.utcnow() + timedelta(minutes=10)

    otp_token = models.OTPToken(
        email=request.email,
        otp_code=otp_code,
        expires_at=expires_at,
        is_used=False,
    )
    db.add(otp_token)
    db.commit()

    # Send OTP via email using SMTP
    import smtplib
    from email.mime.text import MIMEText
    
    smtp_host = os.getenv("SMTP_HOST", "")
    smtp_port = int(os.getenv("SMTP_PORT", "587"))
    smtp_user = os.getenv("SMTP_USERNAME", "")
    smtp_pass = os.getenv("SMTP_PASSWORD", "")
    
    if smtp_host and smtp_user and smtp_pass:
        try:
            msg = MIMEText(f"Your Maveric AI password reset OTP is: {otp_code}\nThis code will expire in 10 minutes.")
            msg['Subject'] = 'Maveric AI Password Reset OTP'
            msg['From'] = smtp_user
            msg['To'] = request.email
            
            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.send_message(msg)
        except Exception as e:
            # Fallback for dev if email fails
            print(f"Failed to send email: {e}. OTP for {request.email} is: {otp_code}")
    else:
        # Fallback if no SMTP configured
        print(f"SMTP not configured. Dev OTP for {request.email} is: {otp_code}")

    response: dict = {
        "status": "SUCCESS",
        "message": "OTP sent to your email address",
        "email": request.email,
    }
    
    return response


@router.post("/forgot-password/verify-otp")
def verify_otp(request: ForgotPasswordVerifyOTPRequest, db: Session = Depends(get_db)):
    record = (
        db.query(models.OTPToken)
        .filter(
            models.OTPToken.email == request.email,
            models.OTPToken.otp_code == request.otp,
            models.OTPToken.is_used == False,
            models.OTPToken.expires_at > datetime.utcnow(),
        )
        .order_by(models.OTPToken.id.desc())
        .first()
    )

    if not record:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP",
        )

    record.is_used = True
    db.commit()

    # Issue a short-lived signed reset token — required by reset-password endpoint
    reset_token = auth.create_reset_token(request.email)
    return {
        "status": "SUCCESS",
        "message": "OTP verified successfully",
        "reset_token": reset_token,
    }


@router.post("/forgot-password/reset-password")
def reset_password(request: ResetPasswordRequest, db: Session = Depends(get_db)):
    # Validate the reset token (signed JWT, expires in 15 min)
    try:
        payload = auth.decode_token(request.reset_token)
    except HTTPException:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired reset token. Please request a new OTP.",
        )

    if payload.get("type") != "reset":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type",
        )

    email = payload.get("email")
    if not email:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid reset token")

    if len(request.new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Password must be at least 6 characters",
        )

    user = db.query(models.User).filter(models.User.email == email).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    user.password_hash = auth.hash_password(request.new_password)
    db.commit()

    return {"status": "SUCCESS", "message": "Password reset successfully"}


@router.post("/refresh")
def refresh_token(request: RefreshTokenRequest):
    payload = auth.decode_token(request.refresh_token)
    if payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type",
        )

    user_id = payload.get("sub")
    email = payload.get("email")

    new_access_token = auth.create_access_token({"sub": user_id, "email": email})
    return {"access_token": new_access_token, "token_type": "bearer"}


@router.get("/me")
def get_me(user_id: Optional[int] = Depends(auth.get_current_user_id), db: Session = Depends(get_db)):
    if user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return {
        "user_id": user.id,
        "name": user.name,
        "email": user.email,
        "profile_photo": user.profile_photo,
        "google_id": user.google_id,
    }
