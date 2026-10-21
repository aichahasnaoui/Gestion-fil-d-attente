from flask_socketio import join_room, leave_room
from flask_jwt_extended import decode_token
from ..extensions import socketio

@socketio.on('connect')
def on_connect(auth):
    token = (auth or {}).get('token')
    if token:
        try:
            data = decode_token(token)
            uid = data['sub']
            join_room(f'user_{uid}')
            # Also join service room if service_admin
            role = data.get('role', '')
            if role == 'service_admin':
                from ..models import ServiceAdminProfile
                from ..extensions import db
                profile = ServiceAdminProfile.query.filter_by(user_id=int(uid)).first()
                if profile and profile.service_id:
                    join_room(f'service_{profile.service_id}')
        except Exception:
            pass

@socketio.on('join_service')
def on_join_service(data):
    sid = data.get('service_id')
    if sid:
        join_room(f'service_{sid}')

@socketio.on('leave_service')
def on_leave_service(data):
    sid = data.get('service_id')
    if sid:
        leave_room(f'service_{sid}')

@socketio.on('join_user')
def on_join_user(data):
    uid = data.get('user_id')
    if uid:
        join_room(f'user_{uid}')

@socketio.on('disconnect')
def on_disconnect():
    pass
