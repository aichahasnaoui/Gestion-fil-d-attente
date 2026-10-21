import uuid
from datetime import date, datetime
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from ..extensions import db, socketio
from ..models import Ticket, Queue, Service, Notification, User

tickets_bp = Blueprint('tickets', __name__)

def _get_or_create_queue(service_id):
    today = date.today()
    queue = Queue.query.filter_by(service_id=service_id, date=today).first()
    if not queue:
        queue = Queue(service_id=service_id, date=today)
        db.session.add(queue)
        db.session.flush()
    return queue

def _ahead_count(queue_id, ticket_number):
    return Ticket.query.filter(
        Ticket.queue_id == queue_id,
        Ticket.ticket_number < ticket_number,
        Ticket.status.in_(['waiting', 'called', 'confirmed'])
    ).count()

def _active_waiting_count(queue_id):
    return Ticket.query.filter(
        Ticket.queue_id == queue_id,
        Ticket.status.in_(['waiting', 'called', 'confirmed'])
    ).count()

def _queue_payload(queue):
    return {
        'service_id': queue.service_id,
        'queue_id': queue.id,
        'current_number': queue.current_number,
        'total_issued': queue.total_issued,
        'total_waiting': _active_waiting_count(queue.id),
        'avg_wait_minutes': queue.avg_wait_minutes,
        'is_open': queue.is_open,
    }

def _emit_queue_update(queue):
    socketio.emit('queue_update', _queue_payload(queue),
                  room=f'service_{queue.service_id}')

def _send_notification(user_id, ntype, title, body, data=None):
    notif = Notification(user_id=user_id, type=ntype, title=title, body=body, data=data)
    db.session.add(notif)
    db.session.flush()
    socketio.emit('notification', notif.to_dict(), room=f'user_{user_id}')
    return notif


@tickets_bp.post('/tickets')
@jwt_required()
def issue_ticket():
    uid = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    service_id = data.get('service_id')
    if not service_id:
        return jsonify(error='service_id is required'), 400
    service = Service.query.get_or_404(service_id)
    if not service.is_active:
        return jsonify(error='Service is not active'), 400

    queue = _get_or_create_queue(service_id)
    if not queue.is_open:
        return jsonify(error='Queue is closed'), 400

    # Check user doesn't already have an active ticket for this queue
    existing = Ticket.query.filter_by(queue_id=queue.id, user_id=uid).filter(
        Ticket.status.in_(['waiting', 'called', 'confirmed'])
    ).first()
    if existing:
        ahead = _ahead_count(existing.queue_id, existing.ticket_number)
        return jsonify(error='You already have an active ticket',
                       ticket=existing.to_dict(ahead),
                       queue=_queue_payload(queue)), 409

    # Check max 3 tickets per day per service
    today_count = Ticket.query.filter(
        Ticket.queue_id == queue.id,
        Ticket.user_id == uid
    ).count()
    if today_count >= 3:
        return jsonify(
            error='Vous avez atteint le maximum de 3 tickets par jour pour ce service.'
        ), 429

    queue.total_issued += 1
    ticket_number = queue.total_issued
    ahead = _ahead_count(queue.id, ticket_number)
    estimated = ahead * queue.avg_wait_minutes

    ticket = Ticket(
        queue_id=queue.id, user_id=uid,
        ticket_number=ticket_number,
        qr_code=str(uuid.uuid4()),
        estimated_wait_min=estimated,
    )
    db.session.add(ticket)
    db.session.flush()

    _send_notification(uid, 'system', f'Ticket #{ticket_number} issued',
                       f'You are #{ticket_number} at {service.name}. ~{estimated} min wait.',
                       {'ticket_id': ticket.id, 'service_id': service_id})
    db.session.commit()

    _emit_queue_update(queue)

    return jsonify(ticket=ticket.to_dict(ahead), queue=_queue_payload(queue)), 201


@tickets_bp.get('/tickets/my')
@jwt_required()
def my_tickets():
    uid = int(get_jwt_identity())
    tickets = Ticket.query.filter_by(user_id=uid).order_by(Ticket.issued_at.desc()).limit(20).all()
    result = []
    for t in tickets:
        if t.status in ['waiting', 'called', 'confirmed']:
            ahead = _ahead_count(t.queue_id, t.ticket_number)
        else:
            ahead = 0
        result.append(t.to_dict(ahead))
    return jsonify(tickets=result), 200


@tickets_bp.get('/tickets/<int:tid>')
@jwt_required()
def get_ticket(tid):
    t = Ticket.query.get_or_404(tid)
    ahead = _ahead_count(t.queue_id, t.ticket_number) if t.status in ['waiting','called','confirmed'] else 0
    return jsonify(ticket=t.to_dict(ahead)), 200


@tickets_bp.post('/tickets/<int:tid>/confirm')
@jwt_required()
def confirm_ticket(tid):
    uid = int(get_jwt_identity())
    ticket = Ticket.query.get_or_404(tid)
    if ticket.user_id != uid:
        return jsonify(error='Forbidden'), 403
    if ticket.status not in ['waiting', 'called', 'confirmed']:
        return jsonify(error='Ce ticket ne peut plus etre confirme.'), 400
    if ticket.confirmation_count >= 3:
        ahead = _ahead_count(ticket.queue_id, ticket.ticket_number)
        return jsonify(ticket=ticket.to_dict(ahead), confirmations_left=0), 200

    ticket.confirmation_count += 1
    if ticket.confirmation_count >= 3:
        ticket.status = 'confirmed'
        _send_notification(uid, 'system', 'Présence confirmée ✅',
                           'Votre présence est confirmée. Présentez-vous au guichet !',
                           {'ticket_id': ticket.id})
    db.session.commit()
    ahead = _ahead_count(ticket.queue_id, ticket.ticket_number)
    return jsonify(ticket=ticket.to_dict(ahead),
                   confirmations_left=3 - ticket.confirmation_count), 200


@tickets_bp.post('/tickets/<int:tid>/cancel')
@jwt_required()
def cancel_ticket(tid):
    uid = int(get_jwt_identity())
    ticket = Ticket.query.get_or_404(tid)
    if ticket.user_id != uid:
        return jsonify(error='Forbidden'), 403
    if ticket.status in ['served', 'cancelled', 'no_show']:
        return jsonify(error='Cannot cancel this ticket'), 400

    ticket.status = 'cancelled'
    ticket.cancelled_at = datetime.utcnow()
    data = request.get_json(silent=True, force=True) or {}
    ticket.cancel_reason = data.get('reason', '')
    db.session.commit()

    _emit_queue_update(ticket.queue)
    return jsonify(message='Ticket cancelled'), 200


@tickets_bp.get('/tickets/queue/<int:service_id>')
@jwt_required()
def live_queue(service_id):
    today = date.today()
    queue = Queue.query.filter_by(service_id=service_id, date=today).first()
    if not queue:
        return jsonify(tickets=[], current_number=0, total_waiting=0,
                       avg_wait_minutes=0, is_open=False), 200
    tickets = Ticket.query.filter_by(queue_id=queue.id).filter(
        Ticket.status.in_(['waiting', 'called', 'confirmed'])
    ).order_by(Ticket.ticket_number).all()
    return jsonify(
        tickets=[t.to_dict(_ahead_count(t.queue_id, t.ticket_number)) for t in tickets],
        current_number=queue.current_number,
        total_waiting=_active_waiting_count(queue.id),
        avg_wait_minutes=queue.avg_wait_minutes,
        is_open=queue.is_open,
    ), 200
