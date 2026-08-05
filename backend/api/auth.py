"""Auth routes: register, login, refresh (rotated), logout, /me, Google OAuth.

Login bookkeeping (last_login_at) is a single commit on the already-loaded User
object -- not a separate query + separate commit -- per
agent_framework/docs/design/AUTH_LOGIN_SESSION_RACE.md's Fix 2 (two sequential
commits on one request session was the actual root cause of a real login-race
incident there; a single atomic write avoids the whole class of bug)."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.auth import google as google_auth
from backend.auth.dependencies import get_current_user
from backend.auth.security import (
    create_access_token,
    get_valid_refresh_token,
    hash_password,
    issue_refresh_token,
    revoke_refresh_token,
    verify_password,
)
from backend.config import settings
from backend.database import get_db
from backend.models.user import User
from backend.schemas.auth import (
    GoogleAuthorizeResponse,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)

router = APIRouter(prefix="/api/auth", tags=["auth"])

# In-memory OAuth state store is fine for a single-process dev/small deployment;
# Phase 6 hardening should move this to Redis if the backend ever runs >1 worker.
_oauth_states: set[str] = set()


def _user_response(user: User) -> UserResponse:
    return UserResponse(
        id=user.id,
        email=user.email,
        display_name=user.display_name,
        avatar_url=user.avatar_url,
        created_at=user.created_at,
        has_password=user.hashed_password is not None,
        has_google=user.google_id is not None,
    )


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest, db: AsyncSession = Depends(get_db)):
    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")

    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        display_name=payload.display_name,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)

    access_token = create_access_token(user.id)
    refresh_token = await issue_refresh_token(user.id, db)
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == payload.email))
    user = result.scalar_one_or_none()

    if user is None or user.hashed_password is None or not verify_password(
        payload.password, user.hashed_password
    ):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

    # Single atomic write for login bookkeeping -- see module docstring.
    user.last_login_at = datetime.now(timezone.utc)
    await db.commit()

    access_token = create_access_token(user.id)
    refresh_token = await issue_refresh_token(user.id, db)
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(payload: RefreshRequest, db: AsyncSession = Depends(get_db)):
    old_token = await get_valid_refresh_token(payload.refresh_token, db)
    new_access_token = create_access_token(old_token.user_id)
    new_refresh_token = await issue_refresh_token(old_token.user_id, db, replaces=old_token)
    return TokenResponse(access_token=new_access_token, refresh_token=new_refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(payload: RefreshRequest, db: AsyncSession = Depends(get_db)):
    await revoke_refresh_token(payload.refresh_token, db)


@router.get("/me", response_model=UserResponse)
async def me(current_user: User = Depends(get_current_user)):
    return _user_response(current_user)


@router.get("/google/authorize", response_model=GoogleAuthorizeResponse)
async def google_authorize():
    state = google_auth.generate_state_token()
    _oauth_states.add(state)
    return GoogleAuthorizeResponse(authorization_url=google_auth.build_authorization_url(state))


@router.get("/google/callback")
async def google_callback(code: str, state: str, db: AsyncSession = Depends(get_db)):
    if state not in _oauth_states:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired state")
    _oauth_states.discard(state)

    try:
        info = await google_auth.exchange_code_for_user_info(code)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    result = await db.execute(select(User).where(User.google_id == info["sub"]))
    user = result.scalar_one_or_none()

    if user is None:
        # No Google-linked account yet -- link to an existing password account with
        # the same email if one exists, otherwise create a new Google-only account.
        result = await db.execute(select(User).where(User.email == info["email"]))
        user = result.scalar_one_or_none()
        if user is None:
            user = User(
                email=info["email"],
                google_id=info["sub"],
                display_name=info.get("name"),
                avatar_url=info.get("picture"),
            )
            db.add(user)
        else:
            user.google_id = info["sub"]
            if not user.avatar_url:
                user.avatar_url = info.get("picture")

    user.last_login_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(user)

    access_token = create_access_token(user.id)
    refresh_token = await issue_refresh_token(user.id, db)

    # Hand tokens to the SPA via a redirect with a URL fragment (never sent to the
    # server in the follow-up navigation, unlike a query string).
    redirect_url = (
        f"{settings.frontend_base_url}/auth/callback"
        f"#access_token={access_token}&refresh_token={refresh_token}"
    )
    return RedirectResponse(url=redirect_url)
