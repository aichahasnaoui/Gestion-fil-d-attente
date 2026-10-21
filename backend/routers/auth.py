from fastapi import APIRouter, HTTPException, Body
from pydantic import BaseModel, Field, ConfigDict
import uuid
from database import get_pool
from auth_utils import hash_password, verify_password, create_access_token, create_refresh_token, decode_token

router = APIRouter()

class RegisterBody(BaseModel):
    full_name: str = Field(..., alias="full_name")
    email: str
    password: str = Field(..., validation_alias="mot_de_passe")
    password: str = Field(..., alias="mot_de_passe")
    role: str
    phone: str | None = Field(None, alias="telephone")
    specialty: str | None = Field(None, alias="specialite")
    service_id: int | None = Field(None, alias="service_id")
    service_id: int | None = None

    model_config = ConfigDict(populate_by_name=True)

class LoginBody(BaseModel):
    email_or_phone: str = Field(..., validation_alias="email")
    password: str = Field(..., validation_alias="mot_de_passe")

    model_config = ConfigDict(populate_by_name=True)

class RefreshBody(BaseModel):
    refresh_token: str

@router.post("/register", status_code=201)
async def register(body: RegisterBody):
    if body.role not in ("patient", "medecin", "client", "service_admin"):
        raise HTTPException(400, "Rôle invalide")
    pool = get_pool()
    
    # On sépare le nom complet pour la base de données (ex: "Jean Dupont" -> "Jean", "Dupont")
    full_name_clean = body.full_name.strip()
    parts = full_name_clean.split(" ", 1)
    prenom, nom = parts[0], (parts[1] if len(parts) > 1 else "")
    

    email = body.email.strip().lower()
    # Si le téléphone est une chaîne vide, on le considère comme None
    phone = body.phone.strip() if (body.phone and body.phone.strip()) else None

    async with pool.acquire() as conn:
        # Vérification email unique
        if await conn.fetchval("SELECT id FROM users WHERE email = $1", email):
            raise HTTPException(400, "Cet email est déjà utilisé")
        
        # Vérification téléphone unique (si fourni)
        if phone and await conn.fetchval("SELECT id FROM users WHERE telephone = $1", phone):
            raise HTTPException(400, "Ce numéro de téléphone est déjà utilisé")

        user_id = str(uuid.uuid4())
        # Utilisation des noms de colonnes qui correspondent à models.py (full_name, phone, password_hash)
        # Assurez-vous que votre table SQL a ces noms ou adaptez ci-dessous:
        await conn.execute(
            "INSERT INTO users (id,nom,prenom,email,mot_de_passe,role,telephone,est_actif,service_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)",
            user_id, nom, prenom, email, hash_password(body.password), body.role, phone, True, body.service_id)
            "INSERT INTO users (id, full_name, email, password_hash, role, phone, is_active) "
            "VALUES ($1, $2, $3, $4, $5, $6, $7)",
            user_id, body.full_name, email, hash_password(body.password), body.role, phone, True
        )
        if body.role == "medecin":
            await conn.execute("INSERT INTO profils_medecins (user_id,specialite) VALUES ($1,$2)", user_id, body.specialty)
            await conn.execute("INSERT INTO doctor_profiles (user_id, specialty) VALUES ($1, $2)", user_id, body.specialty)
        elif body.role == "service_admin" and body.service_id:
            await conn.execute("INSERT INTO service_admin_profiles (user_id, service_id) VALUES ($1, $2)", user_id, body.service_id)

    access = create_access_token(user_id, body.role)
    refresh = create_refresh_token(user_id)
    return {"access_token": access, "refresh_token": refresh, "token_type": "bearer", 
            "user": {"id": user_id, "nom": nom, "prenom": prenom, "email": email, "role": body.role, "service_id": body.service_id}}
            "user": {"id": user_id, "full_name": body.full_name, "email": email, "role": body.role}}

@router.post("/login")
async def login(body: LoginBody):
    # Nettoyage de l'identifiant (email ou téléphone)
    raw_id = body.email_or_phone.strip()
    identifier_lower = raw_id.lower()
    pool = get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT id, nom, prenom, email, role, mot_de_passe, est_actif, service_id FROM users "
            "WHERE LOWER(email) = $1 OR telephone = $2",
            "SELECT id, full_name, email, role, password_hash, is_active FROM users "
            "WHERE LOWER(email) = $1 OR phone = $2",
            identifier_lower, raw_id
        )
    if not row or not verify_password(body.password, row["mot_de_passe"]):
    if not row or not verify_password(body.password, row["password_hash"]):
        raise HTTPException(401, "Identifiant ou mot de passe incorrect")
    if not row["est_actif"]:
    if not row["is_active"]:
        raise HTTPException(403, "Compte désactivé")
    user_id = str(row["id"])
    return {"access_token": create_access_token(user_id, row["role"]),
            "refresh_token": create_refresh_token(user_id), "token_type": "bearer",
            "user": {"id": user_id, "nom": row["nom"], "prenom": row["prenom"], "email": row["email"], "role": row["role"], "service_id": row["service_id"]}}
            "user": {"id": user_id, "full_name": row["full_name"], "email": row["email"], "role": row["role"]}}

@router.post("/refresh")
async def refresh(body: RefreshBody):
    payload = decode_token(body.refresh_token)
    if payload.get("type") != "refresh":
        raise HTTPException(401, "Token invalide")
    pool = get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT role,est_actif FROM users WHERE id=$1", payload["sub"])
    if not row or not row["est_actif"]:
        raise HTTPException(401, "Utilisateur introuvable")
    return {"access_token": create_access_token(payload["sub"], row["role"]),
            "refresh_token": create_refresh_token(payload["sub"]), "token_type": "bearer"}