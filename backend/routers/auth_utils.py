from datetime import datetime, timedelta, timezone
import os
from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext

SECRET_KEY = os.getenv("SECRET_KEY", "CHANGEZ_MOI_EN_PRODUCTION")
ALGORITHM  = "HS256"
pwd_ctx    = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer     = HTTPBearer()

def hash_password(plain): return pwd_ctx.hash(plain)
def verify_password(plain, hashed): return pwd_ctx.verify(plain, hashed)

def create_access_token(user_id, role):
    exp = datetime.now(timezone.utc) + timedelta(minutes=60)
    return jwt.encode({"sub": user_id, "role": role, "exp": exp, "type": "access"}, SECRET_KEY, algorithm=ALGORITHM)

def create_refresh_token(user_id):
    exp = datetime.now(timezone.utc) + timedelta(days=30)
    return jwt.encode({"sub": user_id, "exp": exp, "type": "refresh"}, SECRET_KEY, algorithm=ALGORITHM)

def decode_token(token):
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Token invalide ou expiré")

async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    payload = decode_token(credentials.credentials)
    if payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="Token incorrect")
    return {"user_id": payload["sub"], "role": payload["role"]}

async def require_medecin(current=Depends(get_current_user)):
    if current["role"] != "medecin":
        raise HTTPException(status_code=403, detail="Réservé aux médecins")
    return current