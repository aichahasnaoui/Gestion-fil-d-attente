from fastapi import APIRouter, HTTPException, Depends, WebSocket, WebSocketDisconnect, Query
from pydantic import BaseModel
import uuid, json
from database import get_pool
from auth_utils import get_current_user, decode_token

router = APIRouter()

class ConnectionManager:
    def __init__(self): self.active: dict[str, list[WebSocket]] = {}
    async def connect(self, conv_id, ws):
        await ws.accept(); self.active.setdefault(conv_id, []).append(ws)
    def disconnect(self, conv_id, ws):
        if conv_id in self.active and ws in self.active[conv_id]: self.active[conv_id].remove(ws)
    async def broadcast(self, conv_id, data):
        for ws in self.active.get(conv_id, []):
            try: await ws.send_json(data)
            except: pass

manager = ConnectionManager()

@router.websocket("/ws/{conv_id}")
async def ws_messages(conv_id: str, ws: WebSocket, token: str = Query(...)):
    try:
        payload = decode_token(token); user_id = payload["sub"]
    except:
        await ws.close(code=4001); return
    pool = get_pool()
    async with pool.acquire() as conn:
        if not await conn.fetchrow("SELECT id FROM conversations WHERE id=$1 AND (patient_id=$2 OR medecin_id=$2)", conv_id, user_id):
            await ws.close(code=4003); return
    await manager.connect(conv_id, ws)
    try:
        while True:
            data = json.loads(await ws.receive_text())
            if data.get("type") == "message":
                async with pool.acquire() as conn:
                    row = await conn.fetchrow(
                        "INSERT INTO messages (id,conversation_id,expediteur_id,contenu,est_urgent,type_msg) "
                        "VALUES ($1,$2,$3,$4,$5,'texte') RETURNING id,contenu,expediteur_id,est_urgent,lu,created_at",
                        str(uuid.uuid4()), conv_id, user_id, data["contenu"], data.get("est_urgent", False))
                await manager.broadcast(conv_id, {"type": "nouveau_message", "id": str(row["id"]),
                    "conversation_id": conv_id, "expediteur_id": str(row["expediteur_id"]),
                    "contenu": row["contenu"], "est_urgent": row["est_urgent"],
                    "lu": row["lu"], "created_at": row["created_at"].isoformat()})
            elif data.get("type") == "lu":
                async with pool.acquire() as conn:
                    await conn.execute("UPDATE messages SET lu=TRUE,lu_at=NOW() WHERE conversation_id=$1 AND expediteur_id!=$2 AND lu=FALSE", conv_id, user_id)
                await manager.broadcast(conv_id, {"type": "messages_lus", "lu_par": user_id})
    except WebSocketDisconnect:
        manager.disconnect(conv_id, ws)

@router.get("/{conv_id}")
async def get_messages(conv_id: str, page: int = Query(1), limit: int = Query(30), current=Depends(get_current_user)):
    pool = get_pool(); uid = current["user_id"]
    async with pool.acquire() as conn:
        if not await conn.fetchrow("SELECT id FROM conversations WHERE id=$1 AND (patient_id=$2 OR medecin_id=$2)", conv_id, uid):
            raise HTTPException(404, "Conversation introuvable")
        rows = await conn.fetch("""
            SELECT m.*, u.nom AS exp_nom, u.prenom AS exp_prenom, u.role AS exp_role
            FROM messages m JOIN users u ON u.id=m.expediteur_id
            WHERE m.conversation_id=$1 ORDER BY m.created_at DESC LIMIT $2 OFFSET $3
        """, conv_id, limit, (page-1)*limit)
        await conn.execute("UPDATE messages SET lu=TRUE,lu_at=NOW() WHERE conversation_id=$1 AND expediteur_id!=$2 AND lu=FALSE", conv_id, uid)
    return {"page": page, "messages": [dict(r) for r in reversed(rows)]}

class EnvoyerBody(BaseModel):
    contenu: str; est_urgent: bool = False; type_msg: str = "texte"

@router.post("/{conv_id}")
async def envoyer(conv_id: str, body: EnvoyerBody, current=Depends(get_current_user)):
    pool = get_pool(); uid = current["user_id"]
    async with pool.acquire() as conn:
        if not await conn.fetchrow("SELECT id FROM conversations WHERE id=$1 AND (patient_id=$2 OR medecin_id=$2)", conv_id, uid):
            raise HTTPException(404, "Conversation introuvable")
        row = await conn.fetchrow(
            "INSERT INTO messages (id,conversation_id,expediteur_id,contenu,est_urgent,type_msg) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *",
            str(uuid.uuid4()), conv_id, uid, body.contenu, body.est_urgent, body.type_msg)
    await manager.broadcast(conv_id, {"type": "nouveau_message", "id": str(row["id"]),
        "conversation_id": conv_id, "expediteur_id": uid, "contenu": row["contenu"],
        "est_urgent": row["est_urgent"], "lu": row["lu"], "created_at": row["created_at"].isoformat()})
    return dict(row)

@router.put("/{conv_id}/lus")
async def marquer_lus(conv_id: str, current=Depends(get_current_user)):
    pool = get_pool()
    async with pool.acquire() as conn:
        await conn.execute("UPDATE messages SET lu=TRUE,lu_at=NOW() WHERE conversation_id=$1 AND expediteur_id!=$2 AND lu=FALSE", conv_id, current["user_id"])
    return {"ok": True}