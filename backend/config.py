"""
Application configuration with Docker secrets support.

Secrets are read using the _read_secret() pattern (matches memchat/agent_framework
convention):
  1. Direct env var (e.g., APP_SECRET_KEY)
  2. File-based env var (e.g., APP_SECRET_KEY_FILE -> reads file path)
  3. Raises ValueError if neither is set
"""

import os
import logging

logger = logging.getLogger(__name__)


def _read_secret(env_var: str, file_env_var: str | None = None) -> str:
    if file_env_var is None:
        file_env_var = f"{env_var}_FILE"

    value = os.environ.get(env_var)
    if value:
        return value

    file_path = os.environ.get(file_env_var)
    if file_path:
        try:
            with open(file_path, "r") as f:
                value = f.read().strip()
            if value:
                return value
        except FileNotFoundError:
            logger.error(f"Secret file not found: {file_path} (from {file_env_var})")
        except PermissionError:
            logger.error(f"Permission denied reading: {file_path} (from {file_env_var})")

    raise ValueError(
        f"Secret not configured. Set {env_var} env var or {file_env_var} pointing to a file."
    )


def _build_database_url() -> str:
    """Inject the Postgres password (Docker secret or env var) into DATABASE_URL if
    it isn't already present -- matches memchat's config.py pattern."""
    base_url = os.environ.get(
        "DATABASE_URL", "postgresql+asyncpg://games_tutor@localhost:5432/games_tutor"
    )
    try:
        password = _read_secret("POSTGRES_PASSWORD")
    except ValueError:
        logger.warning("POSTGRES_PASSWORD not set, using DATABASE_URL as-is")
        return base_url

    if "://" in base_url and "@" in base_url:
        scheme_user, rest = base_url.split("@", 1)
        if ":" not in scheme_user.split("://", 1)[1]:
            base_url = f"{scheme_user}:{password}@{rest}"
    return base_url


class Settings:
    def __init__(self):
        # Database
        self.database_url = _build_database_url()
        self.database_pool_size = int(os.environ.get("DATABASE_POOL_SIZE", "10"))
        self.database_max_overflow = int(os.environ.get("DATABASE_MAX_OVERFLOW", "5"))
        self.database_pool_timeout = int(os.environ.get("DATABASE_POOL_TIMEOUT", "10"))

        self.redis_url = os.environ.get("REDIS_URL", "redis://localhost:6379/0")

        self.public_base_url = os.environ.get("PUBLIC_BASE_URL", "http://localhost:8000")
        self.frontend_base_url = os.environ.get("FRONTEND_BASE_URL", "http://localhost:3000")

        self.access_token_expire_minutes = int(
            os.environ.get("ACCESS_TOKEN_EXPIRE_MINUTES", "60")
        )
        self.refresh_token_expire_days = int(os.environ.get("REFRESH_TOKEN_EXPIRE_DAYS", "30"))

        # Lazily-loaded secrets
        self._app_secret_key: str | None = None
        self._google_client_id: str | None = None
        self._google_client_secret: str | None = None
        self._openai_api_key: str | None = None

    @property
    def app_secret_key(self) -> str:
        if self._app_secret_key is None:
            self._app_secret_key = _read_secret("APP_SECRET_KEY")
        return self._app_secret_key

    @property
    def google_client_id(self) -> str:
        if self._google_client_id is None:
            self._google_client_id = _read_secret("GOOGLE_CLIENT_ID")
        return self._google_client_id

    @property
    def google_client_secret(self) -> str:
        if self._google_client_secret is None:
            self._google_client_secret = _read_secret("GOOGLE_CLIENT_SECRET")
        return self._google_client_secret

    @property
    def google_redirect_uri(self) -> str:
        return os.environ.get(
            "GOOGLE_REDIRECT_URI", f"{self.public_base_url}/api/auth/google/callback"
        )

    @property
    def openai_api_key(self) -> str:
        if self._openai_api_key is None:
            self._openai_api_key = _read_secret("OPENAI_API_KEY")
        return self._openai_api_key


settings = Settings()
