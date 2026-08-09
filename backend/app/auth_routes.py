import os
import requests

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime, timedelta

from app.database import SessionLocal
from app import models, auth


router = APIRouter(
    prefix="/api/v1/auth",
    tags=["Authentication"],
)


# ============================================================
# MISC CONFIGURATION
# ============================================================

_DEBUG = os.getenv("DEBUG", "false").lower() == "true"


# ============================================================
# DATABASE DEPENDENCY
# ============================================================

def get_db():
    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()


# ============================================================
# REQUEST SCHEMAS
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
    reset_token: str
    new_password: str


class RefreshTokenRequest(BaseModel):
    refresh_token: str


# ============================================================
# AUTH RESPONSE HELPER
# ============================================================

def _build_auth_response(user: models.User) -> dict:
    access_token = auth.create_access_token(
        {
            "sub": str(user.id),
            "email": user.email,
        }
    )

    refresh_token = auth.create_refresh_token(
        {
            "sub": str(user.id),
            "email": user.email,
        }
    )

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
# REGISTER
# ============================================================

@router.post(
    "/register",
    status_code=status.HTTP_201_CREATED,
)
def register(
    request: RegisterRequest,
    db: Session = Depends(get_db),
):
    existing = (
        db.query(models.User)
        .filter(models.User.email == request.email)
        .first()
    )

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


# ============================================================
# LOGIN
# ============================================================

@router.post("/login")
def login(
    request: LoginRequest,
    db: Session = Depends(get_db),
):
    user = (
        db.query(models.User)
        .filter(models.User.email == request.email)
        .first()
    )

    if (
        not user
        or not user.password_hash
        or not auth.verify_password(
            request.password,
            user.password_hash,
        )
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    # Upgrade legacy PBKDF2 hashes to bcrypt.
    if auth.needs_rehash(user.password_hash):
        user.password_hash = auth.hash_password(
            request.password
        )
        db.commit()

    return _build_auth_response(user)


# ============================================================
# GOOGLE AUTHENTICATION
# ============================================================

@router.post("/google")
def google_auth(
    request: GoogleAuthRequest,
    db: Session = Depends(get_db),
):
    user = (
        db.query(models.User)
        .filter(models.User.email == request.email)
        .first()
    )

    if user:

        # Link Google account if not already linked.
        if not user.google_id:
            user.google_id = request.google_id

        # Update profile photo when supplied.
        if request.profile_photo:
            user.profile_photo = request.profile_photo

        db.commit()
        db.refresh(user)

    else:

        # Create a Google-only account.
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


# ============================================================
# FORGOT PASSWORD — REQUEST OTP
# ============================================================

@router.post("/forgot-password/request-otp")
def request_otp(
    request: ForgotPasswordOTPRequest,
    db: Session = Depends(get_db),
):
    """
    Generate and send a password-reset OTP using Brevo's HTTPS API.

    This uses HTTPS instead of SMTP, so it works with Render Free
    without connecting to blocked SMTP ports.

    Required environment variables:
        BREVO_API_KEY=<Brevo API key>
        BREVO_SENDER_EMAIL=<verified Brevo sender email>
        BREVO_SENDER_NAME=Maveric AI
    """

    email = request.email.strip().lower()

    # --------------------------------------------------------
    # Atomic User Lock (Protects against race conditions)
    # --------------------------------------------------------

    user = (
        db.query(models.User)
        .filter(models.User.email == email)
        .with_for_update()
        .first()
    )

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No account found with this email address",
        )

    # --------------------------------------------------------
    # Rate limiting
    # --------------------------------------------------------
    
    now = datetime.utcnow()
    window = now - timedelta(hours=24)

    recent_tokens = (
        db.query(models.OTPToken)
        .filter(models.OTPToken.email == email, models.OTPToken.created_at >= window)
        .order_by(models.OTPToken.created_at.desc())
        .all()
    )

    if recent_tokens:
        last_token = recent_tokens[0]
        cooldown_remaining = 60 - (now - last_token.created_at).total_seconds()
        if cooldown_remaining > 0:
            remaining_seconds = int(cooldown_remaining)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Please wait {remaining_seconds} seconds before requesting another OTP.",
                headers={"Retry-After": str(remaining_seconds)},
            )

    if len(recent_tokens) >= 5:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Daily password reset OTP limit reached. Please try again later.",
        )

    # --------------------------------------------------------
    # Generate OTP
    # --------------------------------------------------------

    otp_code = auth.generate_otp(6)
    expires_at = now + timedelta(minutes=10)

    # --------------------------------------------------------
    # Store OTP
    # --------------------------------------------------------

    otp_token = models.OTPToken(
        email=email,
        otp_code=otp_code,
        expires_at=expires_at,
        is_used=False,
        created_at=now,
    )

    db.add(otp_token)
    db.commit()

    # --------------------------------------------------------
    # Brevo configuration
    # --------------------------------------------------------

    brevo_api_key = os.getenv(
        "BREVO_API_KEY",
        "",
    ).strip()

    sender_email = os.getenv(
        "BREVO_SENDER_EMAIL",
        "",
    ).strip().lower()

    sender_name = os.getenv(
        "BREVO_SENDER_NAME",
        "Maveric AI",
    ).strip()

    if not brevo_api_key or not sender_email:
        try:
            db.delete(otp_token)
            db.commit()
        except Exception:
            db.rollback()

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Email service is not configured. Please contact the administrator.",
        )

    # --------------------------------------------------------
    # Email HTML
    # --------------------------------------------------------

    email_html = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Maveric AI Password Reset</title>
</head>

<body style="
    margin:0;
    padding:0;
    background:#f4f4f7;
    font-family:Arial,Helvetica,sans-serif;
">

    <div style="
        max-width:600px;
        margin:40px auto;
        background:#ffffff;
        border-radius:16px;
        padding:40px;
        box-shadow:0 4px 20px rgba(0,0,0,0.08);
    ">

        <h1 style="
            margin-top:0;
            color:#6C5CE7;
            text-align:center;
        ">
            Maveric AI
        </h1>

        <h2 style="
            color:#222222;
            text-align:center;
        ">
            Password Reset
        </h2>

        <p style="
            color:#555555;
            font-size:16px;
            line-height:1.6;
        ">
            We received a request to reset your Maveric AI password.
        </p>

        <p style="
            color:#555555;
            font-size:16px;
            line-height:1.6;
        ">
            Your one-time password is:
        </p>

        <div style="
            margin:30px 0;
            padding:20px;
            background:#f1efff;
            border-radius:12px;
            text-align:center;
        ">
            <span style="
                font-size:34px;
                font-weight:bold;
                letter-spacing:10px;
                color:#6C5CE7;
            ">
                {otp_code}
            </span>
        </div>

        <p style="
            color:#555555;
            font-size:15px;
            line-height:1.6;
        ">
            This OTP is valid for <strong>10 minutes</strong>.
        </p>

        <p style="
            color:#777777;
            font-size:14px;
            line-height:1.6;
        ">
            If you did not request a password reset, you can safely ignore
            this email.
        </p>

        <hr style="
            border:none;
            border-top:1px solid #eeeeee;
            margin:30px 0;
        ">

        <p style="
            color:#999999;
            font-size:13px;
            text-align:center;
        ">
            — Maveric AI Team
        </p>

    </div>

</body>
</html>
"""

    # --------------------------------------------------------
    # Send using Brevo HTTPS API
    # --------------------------------------------------------

    try:
        response = requests.post(
            "https://api.brevo.com/v3/smtp/email",
            headers={
                "accept": "application/json",
                "api-key": brevo_api_key,
                "content-type": "application/json",
            },
            json={
                "sender": {
                    "name": sender_name,
                    "email": sender_email,
                },
                "to": [
                    {
                        "email": email,
                    }
                ],
                "subject": "Maveric AI - Password Reset OTP",
                "htmlContent": email_html,
            },
            timeout=15,
        )

    except requests.RequestException as exc:
        print(f"[Brevo] Connection error: {exc}")

        try:
            db.delete(otp_token)
            db.commit()
        except Exception:
            db.rollback()

        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Email service is temporarily unavailable. Please try again later.",
        )

    # --------------------------------------------------------
    # Validate Brevo response
    # --------------------------------------------------------

    if response.status_code not in (200, 201):
        print(
            "[Brevo] Email failed: "
            f"status={response.status_code}, "
            f"response={response.text}"
        )

        try:
            db.delete(otp_token)
            db.commit()
        except Exception:
            db.rollback()

        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Unable to send OTP email. Please try again later.",
        )

    print(
        "[Brevo] Password reset OTP sent successfully "
        f"to {email}"
    )

    return {
        "status": "SUCCESS",
        "message": "OTP sent to your email address",
        "email": email,
    }


# ============================================================
# FORGOT PASSWORD — VERIFY OTP
# ============================================================

@router.post("/forgot-password/verify-otp")
def verify_otp(
    request: ForgotPasswordVerifyOTPRequest,
    db: Session = Depends(get_db),
):
    email = request.email.strip().lower()
    otp = request.otp.strip()

    record = (
        db.query(models.OTPToken)
        .filter(
            models.OTPToken.email == email,
            models.OTPToken.otp_code == otp,
            models.OTPToken.is_used == False,
            models.OTPToken.expires_at > datetime.utcnow(),
        )
        .order_by(
            models.OTPToken.id.desc()
        )
        .first()
    )

    if not record:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP",
        )

    # Mark OTP as used.
    record.is_used = True
    db.commit()

    # Create a short-lived reset token.
    reset_token = auth.create_reset_token(email)

    return {
        "status": "SUCCESS",
        "message": "OTP verified successfully",
        "reset_token": reset_token,
    }


# ============================================================
# FORGOT PASSWORD — RESET PASSWORD
# ============================================================

@router.post("/forgot-password/reset-password")
def reset_password(
    request: ResetPasswordRequest,
    db: Session = Depends(get_db),
):
    # --------------------------------------------------------
    # Validate reset token
    # --------------------------------------------------------

    try:
        payload = auth.decode_token(
            request.reset_token
        )

    except HTTPException:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=(
                "Invalid or expired reset token. "
                "Please request a new OTP."
            ),
        )

    # --------------------------------------------------------
    # Make sure this is a password-reset token
    # --------------------------------------------------------

    if payload.get("type") != "reset":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type",
        )

    email = payload.get("email")

    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid reset token",
        )

    # --------------------------------------------------------
    # Validate password
    # --------------------------------------------------------

    if len(request.new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Password must be at least 6 characters",
        )

    # --------------------------------------------------------
    # Find user
    # --------------------------------------------------------

    user = (
        db.query(models.User)
        .filter(models.User.email == email)
        .first()
    )

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    # --------------------------------------------------------
    # Save new password
    # --------------------------------------------------------

    user.password_hash = auth.hash_password(
        request.new_password
    )

    db.commit()

    return {
        "status": "SUCCESS",
        "message": "Password reset successfully",
    }


# ============================================================
# REFRESH TOKEN
# ============================================================

@router.post("/refresh")
def refresh_token(
    request: RefreshTokenRequest,
):
    payload = auth.decode_token(
        request.refresh_token
    )

    if payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type",
        )

    user_id = payload.get("sub")
    email = payload.get("email")

    new_access_token = auth.create_access_token(
        {
            "sub": user_id,
            "email": email,
        }
    )

    return {
        "access_token": new_access_token,
        "token_type": "bearer",
    }


# ============================================================
# CURRENT USER
# ============================================================

@router.get("/me")
def get_me(
    user_id: Optional[int] = Depends(
        auth.get_current_user_id
    ),
    db: Session = Depends(get_db),
):
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
        )

    user = (
        db.query(models.User)
        .filter(models.User.id == user_id)
        .first()
    )

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return {
        "user_id": user.id,
        "name": user.name,
        "email": user.email,
        "profile_photo": user.profile_photo,
        "google_id": user.google_id,
    }
