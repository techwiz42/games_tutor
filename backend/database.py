"""
Async SQLAlchemy engine + session factory.

Pool config carries forward agent_framework's hard-won lessons (see
agent_framework/docs/design/AUTH_LOGIN_SESSION_RACE.md): pool_pre_ping recovers
server-dropped connections; pool_timeout fails fast on exhaustion rather than
stalling (an unbounded checkout wait is itself part of what widens session races).
"""

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from backend.config import settings

engine = create_async_engine(
    settings.database_url,
    pool_size=settings.database_pool_size,
    max_overflow=settings.database_max_overflow,
    pool_pre_ping=True,
    pool_timeout=settings.database_pool_timeout,
    echo=False,
)

AsyncSessionLocal = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
