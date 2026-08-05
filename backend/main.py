from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.api import auth as auth_api
from backend.config import settings

app = FastAPI(title="games_tutor")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.frontend_base_url],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_api.router)


@app.get("/api/health")
async def health():
    return {"status": "ok"}
