Local dev secrets (gitignored -- never commit real values here).

Required files for `docker compose up`:
- `postgres_password.txt` -- any random string, used by both the postgres and
  backend services.
- `app_secret_key.txt` -- random string, JWT signing key. Generate with:
  `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`
- `openai_api_key.txt` -- real OpenAI API key, needed for the voice tutor.
