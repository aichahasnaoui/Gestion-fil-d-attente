import os
import uuid
from flask import Blueprint, current_app, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from ..extensions import db, socketio
from ..models import Conversation, DoctorProfile, MedicalRecord, Message, Notification, User

messages_bp = Blueprint('messages', __name__)
ALLOWED_ATTACHMENTS = {'png', 'jpg', 'jpeg', 'pdf'}


def _current_user():
    return User.query.get_or_404(int(get_jwt_identity()))


def _conversation_for_user(cid, user):
    conv = Conversation.query.get_or_404(cid)
    if user.role == 'doctor' and user.doctor_profile and conv.doctor_id == user.doctor_profile.id:
        return conv
    if conv.patient_id == user.id:
        return conv
    return None


def _notify_message(recipient_id, sender_name, conv, body):
    preview = body.strip() or 'Piece jointe envoyee'
    notif = Notification(
        user_id=recipient_id,
        type='doctor_response',
        title=f'Nouveau message de {sender_name}',
        body=preview[:180],
        data={'conversation_id': conv.id, 'record_id': conv.record_id},
    )
    db.session.add(notif)
    db.session.flush()
    socketio.emit('notification', notif.to_dict(), room=f'user_{recipient_id}')


def _save_attachment(file_storage):
    if not file_storage or not file_storage.filename:
        return None
    if '.' not in file_storage.filename:
        raise ValueError('Type de fichier non autorise.')

    ext = file_storage.filename.rsplit('.', 1)[1].lower()
    if ext not in ALLOWED_ATTACHMENTS:
        raise ValueError('Type de fichier non autorise. Utilisez png, jpg, jpeg ou pdf.')

    filename = f'message_{uuid.uuid4()}.{ext}'
    folder = os.path.abspath(current_app.config['UPLOAD_FOLDER'])
    os.makedirs(folder, exist_ok=True)
    file_storage.save(os.path.join(folder, filename))
    return {
        'url': f'/api/uploads/{filename}',
        'type': ext,
        'name': file_storage.filename,
    }


@messages_bp.get('/conversations')
@jwt_required()
def list_conversations():
    user = _current_user()
    if user.role == 'doctor' and user.doctor_profile:
        q = Conversation.query.filter_by(doctor_id=user.doctor_profile.id)
    else:
        q = Conversation.query.filter_by(patient_id=user.id)
    conversations = q.order_by(Conversation.updated_at.desc()).all()
    return jsonify(conversations=[c.to_dict() for c in conversations]), 200


@messages_bp.post('/conversations')
@jwt_required()
def create_conversation():
    user = _current_user()
    if user.role not in ['patient', 'client']:
        return jsonify(error='Seul le patient peut demarrer une conversation.'), 403

    attachment = None
    if request.content_type and request.content_type.startswith('multipart/form-data'):
        data = request.form
        try:
            attachment = _save_attachment(request.files.get('file'))
        except ValueError as e:
            return jsonify(error=str(e)), 400
    else:
        data = request.get_json(silent=True) or {}
    doctor_id = data.get('doctor_id')
    body = (data.get('message') or '').strip()
    if not doctor_id:
        return jsonify(error='doctor_id est obligatoire.'), 400
    if not body and not attachment:
        return jsonify(error='Le message ou la piece jointe est obligatoire.'), 400

    doctor = DoctorProfile.query.get_or_404(int(doctor_id))
    record = None
    record_id = data.get('record_id')
    if record_id:
        record = MedicalRecord.query.get_or_404(int(record_id))
        if record.patient_id != user.id:
            return jsonify(error='Dossier interdit.'), 403
        record.is_shared_with_doctor = True
        record.shared_with_doctor_id = doctor.id

    subject = (data.get('subject') or '').strip()
    if not subject:
        subject = record.title if record else 'Question medicale'

    conv = Conversation(
        patient_id=user.id,
        doctor_id=doctor.id,
        record_id=record.id if record else None,
        subject=subject,
    )
    db.session.add(conv)
    db.session.flush()

    msg = Message(
        conversation_id=conv.id,
        sender_id=user.id,
        body=body,
        attachment_url=attachment['url'] if attachment else None,
        attachment_type=attachment['type'] if attachment else None,
        attachment_name=attachment['name'] if attachment else None,
    )
    db.session.add(msg)
    _notify_message(doctor.user_id, user.full_name, conv, body)
    db.session.commit()

    socketio.emit('message', msg.to_dict(), room=f'user_{doctor.user_id}')
    return jsonify(conversation=conv.to_dict(), message=msg.to_dict()), 201


@messages_bp.get('/conversations/<int:cid>/messages')
@jwt_required()
def list_messages(cid):
    user = _current_user()
    conv = _conversation_for_user(cid, user)
    if conv is None:
        return jsonify(error='Forbidden'), 403
    messages = Message.query.filter_by(conversation_id=cid)\
        .order_by(Message.created_at.asc()).all()
    return jsonify(conversation=conv.to_dict(), messages=[m.to_dict() for m in messages]), 200


@messages_bp.post('/conversations/<int:cid>/messages')
@jwt_required()
def send_message(cid):
    user = _current_user()
    conv = _conversation_for_user(cid, user)
    if conv is None:
        return jsonify(error='Forbidden'), 403

    attachment = None
    if request.content_type and request.content_type.startswith('multipart/form-data'):
        body = (request.form.get('body') or '').strip()
        try:
            attachment = _save_attachment(request.files.get('file'))
        except ValueError as e:
            return jsonify(error=str(e)), 400
    else:
        data = request.get_json(silent=True) or {}
        body = (data.get('body') or '').strip()
    if not body and not attachment:
        return jsonify(error='Le message ou la piece jointe est obligatoire.'), 400

    msg = Message(
        conversation_id=conv.id,
        sender_id=user.id,
        body=body,
        attachment_url=attachment['url'] if attachment else None,
        attachment_type=attachment['type'] if attachment else None,
        attachment_name=attachment['name'] if attachment else None,
    )
    db.session.add(msg)
    db.session.flush()
    conv.updated_at = msg.created_at

    recipient_id = conv.patient_id
    if user.id == conv.patient_id and conv.doctor and conv.doctor.user_id:
        recipient_id = conv.doctor.user_id

    _notify_message(recipient_id, user.full_name, conv, body)
    db.session.commit()

    socketio.emit('message', msg.to_dict(), room=f'user_{recipient_id}')
    return jsonify(message=msg.to_dict()), 201
