from fastapi import APIRouter, HTTPException, Depends
import uuid
from database import get_pool
from auth_utils import get_current_user

router = APIRouter()

@router.post("/get-or-create")
async def get_or_create(body: dict, current=Depends(get_current_user)):
    pool = get_pool()
    if current["role"] == "patient":
        patient_id, medecin_id = current["user_id"], body.get("medecin_id")
    else:
        medecin_id, patient_id = current["user_id"], body.get("patient_id")
    async with pool.acquire() as conn:
        if not await conn.fetchval("SELECT id FROM suivis WHERE patient_id=$1 AND medecin_id=$2 AND actif=TRUE", patient_id, medecin_id):
            raise HTTPException(403, "Aucun suivi médical")
        conv = await conn.fetchrow("SELECT * FROM conversations WHERE patient_id=$1 AND medecin_id=$2", patient_id, medecin_id)
        if conv: return dict(conv)
        row = await conn.fetchrow(
            "INSERT INTO conversations (id,patient_id,medecin_id) VALUES ($1,$2,$3) RETURNING *",
            str(uuid.uuid4()), patient_id, medecin_id)
        return dict(row)

@router.get("/")
async def list_conversations(current=Depends(get_current_user)):
    pool = get_pool()
    uid = current["user_id"]
    filtre = "patient_id=$1" if current["role"] == "patient" else "medecin_id=$1"
    async with pool.acquire() as conn:
        rows = await conn.fetch(f"""
            SELECT c.id, c.patient_id, c.medecin_id, c.updated_at,
              (SELECT contenu    FROM messages WHERE conversation_id=c.id ORDER BY created_at DESC LIMIT 1) AS dernier_message,
              (SELECT created_at FROM messages WHERE conversation_id=c.id ORDER BY created_at DESC LIMIT 1) AS dernier_message_at,
              (SELECT COUNT(*)   FROM messages WHERE conversation_id=c.id AND lu=FALSE AND expediteur_id!=$1) AS non_lus,
              p.nom AS patient_nom, p.prenom AS patient_prenom,
              m.nom AS medecin_nom, m.prenom AS medecin_prenom,
              pm.specialite
            FROM conversations c
            JOIN users p ON p.id=c.patient_id
            JOIN users m ON m.id=c.medecin_id
            LEFT JOIN profils_medecins pm ON pm.user_id=c.medecin_id
            WHERE c.{filtre} ORDER BY c.updated_at DESC
        """, uid)
    return [dict(r) for r in rows]