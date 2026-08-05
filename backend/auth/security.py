"""Password hashing, JWT access tokens, and refresh-token issuance/rotation.

Access tokens are short-lived, stateless JWTs (matches memchat's jwt.py pattern).
Refresh tokens are DB-persisted and hashed at rest -- the raw token is returned to
the client exactly once (at issuance) and never stored; only its SHA-256 hash is
kept, so a DB leak alone can't be used to impersonate a user (see docs/PLAN.md's
auth decision -- this is deliberately stronger than both thanotopolis's plaintext
DB-stored token and memchat's stateless-JWT-with-no-revocation refresh token).
"""

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.config import settings
from backend.models.refresh_token import RefreshToken

ALGORITHM = "HS256"

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
_bearer_scheme = HTTPBearer()


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(user_id: uuid.UUID) -> str:
    payload = {
        "sub": str(user_id),
        "exp": datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes),
        "type": "access",
    }
    return jwt.encode(payload, settings.app_secret_key, algorithm=ALGORITHM)


def decode_access_token(token: str) -> uuid.UUID:
    """Raises HTTPException(401) if invalid, expired, or wrong token type."""
    try:
        payload = jwt.decode(token, settings.app_secret_key, algorithms=[ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    if payload.get("type") != "access":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token type")

    try:
        return uuid.UUID(payload["sub"])
    except (KeyError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")


def _hash_refresh_token(raw_token: str) -> str:
    return hashlib.sha256(raw_token.encode()).hexdigest()


async def issue_refresh_token(
    user_id: uuid.UUID, db: AsyncSession, replaces: Optional[RefreshToken] = None
) -> str:
    """Create and persist a new refresh token, returning the raw (unhashed) value.
    If `replaces` is given, chains it to the new token (rotation) and revokes it."""
    raw_token = secrets.token_urlsafe(32)
    new_row = RefreshToken(
        user_id=user_id,
        token_hash=_hash_refresh_token(raw_token),
        expires_at=datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_expire_days),
    )
    db.add(new_row)

    if replaces is not None:
        await db.flush()  # assign new_row.id before we reference it
        replaces.revoked_at = datetime.now(timezone.utc)
        replaces.replaced_by_token_id = new_row.id

    await db.commit()
    return raw_token


async def get_valid_refresh_token(raw_token: str, db: AsyncSession) -> RefreshToken:
    """Look up a refresh token by its hash and validate it's usable.

    A reused, already-rotated token (revoked_at set, replaced_by_token_id set) is a
    theft signal -- the caller should treat that as suspicious, not just "invalid".
    """
    token_hash = _hash_refresh_token(raw_token)
    result = await db.execute(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
    row = result.scalar_one_or_none()

    if row is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

    now = datetime.now(timezone.utc)
    if row.expires_at.replace(tzinfo=timezone.utc) < now:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired")

    if row.revoked_at is not None:
        if row.replaced_by_token_id is not None:
            # Reuse of a rotated-away token is a theft signal, not an ordinary
            # revoke (e.g. logout) -- revoke the entire chain defensively.
            await _revoke_token_chain(row, db)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Refresh token already used (possible theft) -- all sessions revoked",
            )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token revoked")

    return row


async def _revoke_token_chain(token: RefreshToken, db: AsyncSession) -> None:
    """Best-effort revoke of every token in this user's active chain, since we
    can't tell which downstream token (if any) an attacker is holding."""
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.user_id == token.user_id, RefreshToken.revoked_at.is_(None)
        )
    )
    for row in result.scalars().all():
        row.revoked_at = now
    await db.commit()


async def revoke_refresh_token(raw_token: str, db: AsyncSession) -> None:
    token_hash = _hash_refresh_token(raw_token)
    result = await db.execute(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
    row = result.scalar_one_or_none()
    if row is not None and row.revoked_at is None:
        row.revoked_at = datetime.now(timezone.utc)
        await db.commit()


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
) -> uuid.UUID:
    return decode_access_token(credentials.credentials)
