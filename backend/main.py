from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import os
from routers import auth, messages, conversations, users
from database import init_db_pool, close_db_pool

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:password@localhost:5432/medical_chat")

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db_pool(DATABASE_URL)
    yield
    await close_db_pool()

app = FastAPI(title="Messagerie Médicale API", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

app.include_router(auth.router,          prefix="/api/auth",         tags=["Auth"])
app.include_router(users.router,         prefix="/api/users",        tags=["Users"])
app.include_router(conversations.router, prefix="/api/conversations", tags=["Conversations"])
app.include_router(messages.router,      prefix="/api/messages",     tags=["Messages"])

@app.get("/")
async def root():
    return {"status": "ok"}