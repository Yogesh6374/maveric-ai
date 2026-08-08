import os
import random
import string
from datetime import datetime, timedelta
from typing import Optional

# Use bcrypt directly — passlib 1.7.4 is incompatible with bcrypt>=4.x
# (detect_wrap_bug raises ValueError on newer bcrypt versions).
import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

# ============================================================
# CONFIGURATION
# ============================================================

_DEFAULT_SECRET = "maveric_ai_secret_key_2026_jwt_secure_auth_token_string"
SECRET_KEY = os.getenv("JWT_SECRET", _DEFAULT_SECRET)
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 7
REFRESH_TOKEN_EXPIRE_DAYS = 30

# Warn loudly if still using the default secret
if SECRET_KEY == _DEFAULT_SECRET:
    import warnings
    warnings.warn(
        "[SECURITY] JWT_SECRET is using the default insecure key. "
        "Set the JWT_SECRET environment variable before deploying to production.",
        stacklevel=1,
    )

# ============================================================
# PASSWORD HASHING — using bcrypt directly (no passlib)
# ============================================================


def hash_password(password: str) -> str:
    """Hash a plain-text password with bcrypt (work factor 12)."""
    # bcrypt truncates at 72 bytes; handle explicitly for clarity
    pwd_bytes = password.encode("utf-8")[:72]
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(pwd_bytes, salt).decode("utf-8")


def _verify_pbkdf2_passlib(plain_password: str, hashed: str) -> bool:
    """
    Verify a password against a passlib PBKDF2-SHA256 hash WITHOUT passlib.

    Passlib's $pbkdf2-sha256$ format:
        $pbkdf2-sha256$<rounds>$<salt_b64>$<hash_b64>

    The salt and hash use a *modified* base64 alphabet (passlib uses '.' instead of '+',
    and omits '=' padding).  We replicate that here using Python's built-in hashlib.
    """
    import hashlib
    import base64
    import hmac as _hmac

    try:
        # Split the hash string
        parts = hashed.split("$")
        # Expected: ['', 'pbkdf2-sha256', rounds, salt_b64, hash_b64]
        if len(parts) != 5 or parts[1] != "pbkdf2-sha256":
            return False

        rounds = int(parts[2])
        # Passlib uses '.' instead of '+' and no padding
        salt_b64 = parts[3].replace(".", "+")
        # Restore missing '=' padding
        salt_b64 += "=" * (-len(salt_b64) % 4)
        salt = base64.b64decode(salt_b64)

        hash_b64 = parts[4].replace(".", "+")
        hash_b64 += "=" * (-len(hash_b64) % 4)
        expected_hash = base64.b64decode(hash_b64)

        # PBKDF2-HMAC-SHA256 with the same rounds
        computed = hashlib.pbkdf2_hmac(
            "sha256",
            plain_password.encode("utf-8"),
            salt,
            rounds,
            dklen=len(expected_hash),
        )
        # Constant-time comparison
        return _hmac.compare_digest(computed, expected_hash)
    except Exception:
        return False


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a plain-text password against a stored hash.

    Supports:
    1. bcrypt hashes ($2b$ / $2a$ / $2y$) — current format
    2. passlib PBKDF2-SHA256 hashes ($pbkdf2-sha256$) — legacy format

    On successful login with a legacy hash the caller is responsible for
    upgrading the stored hash to bcrypt (see needs_rehash / auth_routes.py).
    """
    if not hashed_password:
        return False
    try:
        if hashed_password.startswith(("$2b$", "$2a$", "$2y$")):
            # bcrypt path
            pwd_bytes = plain_password.encode("utf-8")[:72]
            hash_bytes = hashed_password.encode("utf-8")
            return bcrypt.checkpw(pwd_bytes, hash_bytes)
        elif hashed_password.startswith("$pbkdf2-sha256$"):
            # Legacy passlib PBKDF2 path
            return _verify_pbkdf2_passlib(plain_password, hashed_password)
        else:
            # Unknown format — fall back to safe bcrypt attempt
            pwd_bytes = plain_password.encode("utf-8")[:72]
            return bcrypt.checkpw(pwd_bytes, hashed_password.encode("utf-8"))
    except Exception:
        return False


def needs_rehash(hashed_password: str) -> bool:
    """Return True if the stored hash is a legacy format that should be upgraded to bcrypt."""
    return bool(hashed_password) and not hashed_password.startswith(("$2b$", "$2a$", "$2y$"))


# ============================================================
# JWT TOKENS
# ============================================================

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS))
    to_encode.update({"exp": expire, "type": "access"})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS))
    to_encode.update({"exp": expire, "type": "refresh"})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def create_reset_token(email: str) -> str:
    """Create a short-lived (15 min) password-reset token tied to the user's email."""
    expire = datetime.utcnow() + timedelta(minutes=15)
    data = {"email": email, "type": "reset", "exp": expire}
    return jwt.encode(data, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired",
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )


# ============================================================
# FASTAPI DEPENDENCY — get current authenticated user
# ============================================================

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login", auto_error=False)


def get_current_user_id(token: Optional[str] = Depends(oauth2_scheme)) -> Optional[int]:
    """
    Extracts user_id from Bearer token.
    Returns None if no token provided (allows optional auth).
    Raises 401 if token is present but invalid.
    """
    if not token:
        return None
    payload = decode_token(token)  # raises HTTPException on invalid
    user_id_str = payload.get("sub")
    if not user_id_str:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")
    try:
        return int(user_id_str)
    except (ValueError, TypeError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid user ID in token")


# ============================================================
# OTP GENERATOR
# ============================================================

def generate_otp(length: int = 6) -> str:
    return "".join(random.choices(string.digits, k=length))
