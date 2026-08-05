Local dev secrets (gitignored -- never commit real values here).

Required files for `docker compose up`:
- `postgres_password.txt` -- any random string, used by both the postgres and
  backend services.
- `app_secret_key.txt` -- random string, JWT signing key. Generate with:
  `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`
- `google_client_id.txt` / `google_client_secret.txt` -- only needed for the
  Google OAuth login flow; a placeholder value is fine until that's actually used.
- `openai_api_key.txt` -- real OpenAI API key, only needed once voice (Phase 4)
  is wired up.
