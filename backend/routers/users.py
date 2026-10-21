from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import Optional
from database import get_pool
from auth_utils import get_current_user, require_medecin

router = APIRouter()

@router.get("/me")
async def get_me(current=Depends(get_current_user)):
    pool = get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT u.id,u.nom,u.prenom,u.email,u.role,u.telephone,u.photo_url,
                   pm.specialite,pm.cabinet,pm.disponible,pm.msg_absence
            FROM users u LEFT JOIN profils_medecins pm ON pm.user_id=u.id WHERE u.id=$1
        """, current["user_id"])
    if not row: raise HTTPException(404, "Introuvable")
    return dict(row)

@router.get("/mes-medecins")
async def mes_medecins(current=Depends(get_current_user)):
    if current["role"] != "patient": raise HTTPException(403, "Réservé aux patients")
    pool = get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT u.id,u.nom,u.prenom,u.photo_url,pm.specialite,pm.cabinet,pm.disponible
            FROM suivis s JOIN users u ON u.id=s.medecin_id
            LEFT JOIN profils_medecins pm ON pm.user_id=u.id
            WHERE s.patient_id=$1 AND s.actif=TRUE ORDER BY u.nom
        """, current["user_id"])
    return [dict(r) for r in rows]

@router.get("/mes-patients")
async def mes_patients(current=Depends(require_medecin)):
    pool = get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT u.id,u.nom,u.prenom,u.telephone,
              (SELECT COUNT(*) FROM messages m JOIN conversations c ON c.id=m.conversation_id
               WHERE c.patient_id=u.id AND c.medecin_id=$1 AND m.lu=FALSE AND m.expediteur_id=u.id) AS non_lus
            FROM suivis s JOIN users u ON u.id=s.patient_id
            WHERE s.medecin_id=$1 AND s.actif=TRUE ORDER BY non_lus DESC,u.nom
        """, current["user_id"])
    return [dict(r) for r in rows]

class DispoBody(BaseModel):
    disponible: bool; msg_absence: Optional[str] = None

@router.put("/disponibilite")
async def set_dispo(body: DispoBody, current=Depends(require_medecin)):
    pool = get_pool()
    async with pool.acquire() as conn:
        await conn.execute("UPDATE profils_medecins SET disponible=$1,msg_absence=$2 WHERE user_id=$3",
                           body.disponible, body.msg_absence, current["user_id"])
    return {"disponible": body.disponible}