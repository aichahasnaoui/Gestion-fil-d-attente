from datetime import date, datetime, timedelta
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from ..extensions import db, socketio
from ..models import User, Service, Queue, Ticket, Guichet, ServiceAdminProfile, Notification

service_admin_bp = Blueprint('service_admin', __name__)


def _get_admin_service(uid):
    """Returns (service, error) for the logged-in service admin."""
    user = User.query.get_or_404(uid)
    if user.role != 'service_admin':
        return None, (jsonify(error='Forbidden'), 403)
    profile = ServiceAdminProfile.query.filter_by(user_id=uid).first()
    if not profile or not profile.service_id:
        return None, (jsonify(error='Aucun service assigné à ce compte. Contactez un administrateur.'), 404)
    service = Service.query.get(profile.service_id)
    if not service:
        return None, (jsonify(error='Service introuvable.'), 404)
    return service, None


def _recalc_avg_wait(queue, open_guichets):
    """Recalculate avg wait per ticket based on open guichets.
    Formula: base_minutes / open_guichets
    More guichets = faster service per ticket.
    """
    base = 5  # base minutes per ticket with 1 guichet
    if open_guichets <= 0:
        open_guichets = 1
    queue.avg_wait_minutes = max(1, base // open_guichets)
    db.session.flush()


def _recalc_estimated_wait(queue, open_guichets):
    """Recalculate estimated wait for each waiting ticket.
    estimated_wait = (position_in_queue / open_guichets) * base_minutes
    """
    base = 5
    if open_guichets <= 0:
        open_guichets = 1
    avg = max(1, base // open_guichets)
    queue.avg_wait_minutes = avg
    db.session.flush()


def _notify_waiting_users(service, queue, open_guichets):
    """Notify all waiting users about updated wait time based on position and guichets."""
    from .tickets import _ahead_count
    base = 5
    if open_guichets <= 0:
        open_guichets = 1

    waiting = Ticket.query.filter_by(queue_id=queue.id).filter(
        Ticket.status.in_(['waiting', 'called', 'confirmed'])
    ).all()

    for t in waiting:
        ahead = _ahead_count(queue.id, t.ticket_number)
        # Each person waits: (ahead+1) tickets / open_guichets * base_minutes
        new_wait = max(1, ((ahead + 1) * base) // open_guichets)

        if open_guichets > 1:
            msg = (f'Un nouveau guichet a ouvert chez {service.name}. '
                   f'Votre attente estimée est maintenant ~{new_wait} min. 🎉')
        else:
            msg = (f'Un guichet a été fermé chez {service.name}. '
                   f'Votre attente estimée est maintenant ~{new_wait} min.')

        n = Notification(
            user_id=t.user_id,
            type='ticket_alert',
            title='⏱ Mise à jour du temps d\'attente',
            body=msg,
            data={'ticket_id': t.id, 'service_id': service.id, 'new_wait': new_wait},
        )
        db.session.add(n)
        db.session.flush()
        socketio.emit('notification', n.to_dict(), room=f'user_{t.user_id}')


# ── Dashboard ─────────────────────────────────────────────────────────────────
@service_admin_bp.get('/service-admin/dashboard')
@jwt_required()
def dashboard():
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err

    today = date.today()
    queue = Queue.query.filter_by(service_id=service.id, date=today).first()
    if not queue:
        queue = Queue(service_id=service.id, date=today, is_open=True)
        db.session.add(queue)
        db.session.commit()

    waiting   = Ticket.query.filter_by(queue_id=queue.id, status='waiting').count()
    called    = Ticket.query.filter_by(queue_id=queue.id, status='called').count()
    confirmed = Ticket.query.filter_by(queue_id=queue.id, status='confirmed').count()
    served    = Ticket.query.filter_by(queue_id=queue.id, status='served').count()
    cancelled = Ticket.query.filter_by(queue_id=queue.id).filter(
        Ticket.status.in_(['cancelled', 'no_show'])).count()

    guichets   = Guichet.query.filter_by(service_id=service.id).all()
    open_count = sum(1 for g in guichets if g.is_open)

    # Recalc avg wait based on open guichets
    if open_count > 0:
        _recalc_avg_wait(queue, open_count)
        db.session.commit()

    return jsonify(
        service=service.to_dict(),
        queue={
            'is_open':         queue.is_open,
            'current_number':  queue.current_number,
            'total_issued':    queue.total_issued,
            'avg_wait_minutes': queue.avg_wait_minutes,
            'waiting':   waiting,
            'called':    called,
            'confirmed': confirmed,
            'served':    served,
            'cancelled': cancelled,
        },
        guichets=[g.to_dict() for g in guichets],
        open_guichets=open_count,
    ), 200


# ── Update service settings ───────────────────────────────────────────────────
@service_admin_bp.patch('/service-admin/service')
@jwt_required()
def update_service():
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err

    d = request.get_json()
    if 'max_daily_tickets' in d:
        service.max_daily_tickets = int(d['max_daily_tickets'])
    if 'avg_wait_minutes' in d:
        today = date.today()
        queue = Queue.query.filter_by(service_id=service.id, date=today).first()
        if queue:
            queue.avg_wait_minutes = int(d['avg_wait_minutes'])
    db.session.commit()
    return jsonify(service=service.to_dict()), 200


# ── Toggle queue open/close ───────────────────────────────────────────────────
@service_admin_bp.patch('/service-admin/queue/toggle')
@jwt_required()
def toggle_queue():
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err

    today = date.today()
    queue = Queue.query.filter_by(service_id=service.id, date=today).first()
    if not queue:
        queue = Queue(service_id=service.id, date=today)
        db.session.add(queue)
    queue.is_open = not queue.is_open
    db.session.commit()
    socketio.emit('queue_status', {'service_id': service.id, 'is_open': queue.is_open},
                  room=f'service_{service.id}')
    return jsonify(is_open=queue.is_open), 200


# ── Guichets management ───────────────────────────────────────────────────────
@service_admin_bp.get('/service-admin/guichets')
@jwt_required()
def list_guichets():
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err
    guichets = Guichet.query.filter_by(service_id=service.id).all()
    return jsonify(guichets=[g.to_dict() for g in guichets]), 200


@service_admin_bp.post('/service-admin/guichets')
@jwt_required()
def add_guichet():
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err

    count = Guichet.query.filter_by(service_id=service.id).count()
    g = Guichet(service_id=service.id, name=f'Guichet {count + 1}', is_open=True)
    db.session.add(g)
    db.session.commit()
    return jsonify(guichet=g.to_dict()), 201


@service_admin_bp.patch('/service-admin/guichets/<int:gid>/toggle')
@jwt_required()
def toggle_guichet(gid):
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err

    g = Guichet.query.get_or_404(gid)
    if g.service_id != service.id:
        return jsonify(error='Forbidden'), 403

    g.is_open = not g.is_open
    db.session.flush()

    # Recalculate avg wait based on open guichets
    open_count = Guichet.query.filter_by(service_id=service.id, is_open=True).count()
    today = date.today()
    queue = Queue.query.filter_by(service_id=service.id, date=today).first()
    if queue:
        _recalc_avg_wait(queue, open_count)
        _notify_waiting_users(service, queue, open_count)
        socketio.emit('queue_update', {
            'service_id': service.id,
            'avg_wait_minutes': queue.avg_wait_minutes,
            'open_guichets': open_count,
        }, room=f'service_{service.id}')

    db.session.commit()
    return jsonify(guichet=g.to_dict(), open_guichets=open_count,
                   avg_wait_minutes=queue.avg_wait_minutes if queue else 10), 200


@service_admin_bp.delete('/service-admin/guichets/<int:gid>')
@jwt_required()
def delete_guichet(gid):
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err

    g = Guichet.query.get_or_404(gid)
    if g.service_id != service.id:
        return jsonify(error='Forbidden'), 403
    db.session.delete(g)
    db.session.commit()
    return jsonify(message='Deleted'), 200


# ── Call next ticket ──────────────────────────────────────────────────────────
@service_admin_bp.post('/service-admin/call-next')
@jwt_required()
def call_next():
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err

    today = date.today()
    queue = Queue.query.filter_by(service_id=service.id, date=today).first()
    if not queue or not queue.is_open:
        return jsonify(error='Queue not found or closed'), 404

    # Auto-cancel called ticket if not confirmed after being called
    called_ticket = Ticket.query.filter_by(queue_id=queue.id, status='called').first()
    if called_ticket:
        called_ticket.status = 'no_show'
        called_ticket.cancelled_at = datetime.utcnow()
        n_noshow = Notification(
            user_id=called_ticket.user_id, type='ticket_alert',
            title='❌ Ticket annulé — Absent',
            body=f'Votre ticket #{called_ticket.ticket_number} a été annulé car vous ne vous êtes pas présenté.',
            data={'ticket_id': called_ticket.id, 'service_id': service.id},
        )
        db.session.add(n_noshow)
        db.session.flush()
        socketio.emit('notification', n_noshow.to_dict(), room=f'user_{called_ticket.user_id}')

    # Get next active ticket, including users who already confirmed 3/3.
    ticket = Ticket.query.filter(Ticket.queue_id == queue.id)\
        .filter(Ticket.status.in_(['waiting', 'confirmed']))\
        .order_by(Ticket.ticket_number).first()
    if not ticket:
        db.session.commit()
        return jsonify(error='No waiting tickets'), 404

    ticket.status = 'called'
    ticket.called_at = datetime.utcnow()
    queue.current_number = ticket.ticket_number

    # Notify the called user
    n = Notification(
        user_id=ticket.user_id, type='ticket_alert',
        title=f'🔔 C\'est votre tour ! Ticket {ticket.ticket_number}',
        body=f'Veuillez vous présenter au guichet chez {service.name}. Confirmez votre présence !',
        data={'ticket_id': ticket.id, 'service_id': service.id, 'action': 'confirm_arrival'},
    )
    db.session.add(n)
    db.session.flush()
    socketio.emit('notification', n.to_dict(), room=f'user_{ticket.user_id}')

    # Send confirmation_request to users with exactly 3 people ahead
    from .tickets import _ahead_count
    alert_tickets = Ticket.query.filter_by(
        queue_id=queue.id, status='waiting'
    ).order_by(Ticket.ticket_number).all()

    for t in alert_tickets:
        ahead = _ahead_count(queue.id, t.ticket_number)
        if ahead == 3:
            n_alert = Notification(
                user_id=t.user_id, type='confirmation_request',
                title='⏰ Préparez-vous ! Plus que 3 personnes avant vous',
                body=f'Il reste 3 personnes avant votre tour chez {service.name}. '
                     f'Confirmez votre présence ou votre ticket sera annulé automatiquement.',
                data={
                    'ticket_id': t.id,
                    'service_id': service.id,
                    'ahead': ahead,
                    'action': 'confirm_or_cancel',
                },
            )
            db.session.add(n_alert)
            db.session.flush()
            socketio.emit('notification', n_alert.to_dict(), room=f'user_{t.user_id}')

    db.session.commit()
    socketio.emit('queue_update', {
        'service_id': service.id,
        'current_number': queue.current_number,
    }, room=f'service_{service.id}')
    return jsonify(ticket=ticket.to_dict(), current_number=queue.current_number), 200


# ── Cancel current called ticket (no-show) ───────────────────────────────────
@service_admin_bp.post('/service-admin/cancel-current')
@jwt_required()
def cancel_current():
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err

    today = date.today()
    queue = Queue.query.filter_by(service_id=service.id, date=today).first()
    if not queue:
        return jsonify(error='Aucune file aujourd\'hui'), 404

    # Cancel ticket that is called OR confirmed (present at counter)
    ticket = Ticket.query.filter_by(queue_id=queue.id).filter(
        Ticket.status.in_(['called', 'confirmed'])
    ).order_by(Ticket.ticket_number).first()

    if not ticket:
        return jsonify(error='Aucun ticket en cours d\'appel'), 404

    ticket.status = 'no_show'
    ticket.cancelled_at = datetime.utcnow()

    n = Notification(
        user_id=ticket.user_id, type='ticket_alert',
        title='\u274c Ticket annul\u00e9 \u2014 Absent',
        body=f'Votre ticket #{ticket.ticket_number} a \u00e9t\u00e9 annul\u00e9 car vous ne vous \u00eates pas pr\u00e9sent\u00e9.',
        data={'ticket_id': ticket.id, 'service_id': service.id},
    )
    db.session.add(n)
    db.session.flush()
    socketio.emit('notification', n.to_dict(), room=f'user_{ticket.user_id}')

    db.session.commit()
    socketio.emit('queue_update', {'service_id': service.id},
                  room=f'service_{service.id}')
    return jsonify(message='Ticket annul\u00e9 (absent)', ticket_number=ticket.ticket_number), 200


# ── Auto-cancel unconfirmed called tickets ────────────────────────────────────
@service_admin_bp.post('/service-admin/check-no-shows')
@jwt_required()
def check_no_shows():
    """Cancel tickets that were called but never confirmed (called > 5 min ago)."""
    uid = int(get_jwt_identity())
    service, err = _get_admin_service(uid)
    if err: return err

    today = date.today()
    queue = Queue.query.filter_by(service_id=service.id, date=today).first()
    if not queue:
        return jsonify(cancelled=0), 200

    cutoff = datetime.utcnow() - timedelta(minutes=5)
    stale = Ticket.query.filter(
        Ticket.queue_id == queue.id,
        Ticket.status == 'called',
        Ticket.called_at < cutoff,
        Ticket.confirmation_count == 0,
    ).all()

    cancelled = 0
    for t in stale:
        t.status = 'no_show'
        t.cancelled_at = datetime.utcnow()
        n = Notification(
            user_id=t.user_id, type='ticket_alert',
            title='❌ Ticket annulé automatiquement',
            body=f'Votre ticket #{t.ticket_number} a été annulé car vous ne vous êtes pas présenté à temps.',
            data={'ticket_id': t.id, 'service_id': service.id},
        )
        db.session.add(n)
        db.session.flush()
        socketio.emit('notification', n.to_dict(), room=f'user_{t.user_id}')
        cancelled += 1

    if cancelled > 0:
        db.session.commit()
        socketio.emit('queue_update', {'service_id': service.id},
                      room=f'service_{service.id}')

    return jsonify(cancelled=cancelled), 200


# ── Public: get guichets for a service ───────────────────────────────────────
@service_admin_bp.get('/services/<int:sid>/guichets')
@jwt_required()
def public_guichets(sid):
    guichets = Guichet.query.filter_by(service_id=sid).all()
    open_count = sum(1 for g in guichets if g.is_open)
    return jsonify(guichets=[g.to_dict() for g in guichets], open_count=open_count), 200
