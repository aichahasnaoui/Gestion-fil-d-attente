from datetime import date
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from ..extensions import db
from ..models import Service, Queue, Ticket, Guichet

services_bp = Blueprint('services', __name__)

@services_bp.get('/services/public')
def list_services_public():
    q = Service.query.filter(Service.is_active != False)
    services = q.all()
    result = []
    today = date.today()
    for s in services:
        queue = Queue.query.filter_by(service_id=s.id, date=today).first()
        stats = {}
        if queue:
            waiting = Ticket.query.filter_by(queue_id=queue.id).filter(
                Ticket.status.in_(['waiting', 'called', 'confirmed'])
            ).count()
            stats = {'today_in_queue': waiting, 'today_avg_wait': queue.avg_wait_minutes}
        result.append(s.to_dict(stats))
    return jsonify(services=result), 200


@services_bp.get('/services')
@jwt_required()
def list_services():
    q = Service.query.filter_by(is_active=True)
    if t := request.args.get('type'):
        q = q.filter_by(type=t)
    if w := request.args.get('wilaya'):
        q = q.filter_by(wilaya=w)
    services = q.all()
    result = []
    today = date.today()
    for s in services:
        queue = Queue.query.filter_by(service_id=s.id, date=today).first()
        stats = {}
        if queue:
            waiting = Ticket.query.filter_by(queue_id=queue.id).filter(
                Ticket.status.in_(['waiting', 'called', 'confirmed'])
            ).count()
            open_g = Guichet.query.filter_by(service_id=s.id, is_open=True).count()
            stats = {
                'today_in_queue': waiting,
                'today_avg_wait': queue.avg_wait_minutes,
                'today_total_issued': queue.total_issued,
                'open_guichets': open_g,
            }
        result.append(s.to_dict(stats))
    return jsonify(services=result), 200


@services_bp.get('/services/<int:sid>')
@jwt_required()
def get_service(sid):
    s = Service.query.get_or_404(sid)
    today = date.today()
    queue = Queue.query.filter_by(service_id=sid, date=today).first()
    stats = {}
    if queue:
        waiting = Ticket.query.filter_by(queue_id=queue.id).filter(
            Ticket.status.in_(['waiting', 'called', 'confirmed'])
        ).count()
        stats = {
            'today_in_queue': waiting,
            'today_avg_wait': queue.avg_wait_minutes,
            'today_total_issued': queue.total_issued
        }
    return jsonify(service=s.to_dict(stats)), 200


@services_bp.get('/services/<int:sid>/queue-status')
@jwt_required()
def queue_status(sid):
    today = date.today()
    queue = Queue.query.filter_by(service_id=sid, date=today).first()
    if not queue:
        return jsonify(current_number=0, total_issued=0, waiting=0,
                       avg_wait=0, avg_wait_minutes=0, is_open=False), 200
    waiting = Ticket.query.filter_by(queue_id=queue.id).filter(
        Ticket.status.in_(['waiting', 'called', 'confirmed'])
    ).count()
    return jsonify(
        current_number=queue.current_number,
        total_issued=queue.total_issued,
        waiting=waiting,
        avg_wait=queue.avg_wait_minutes,
        avg_wait_minutes=queue.avg_wait_minutes,
        is_open=queue.is_open,
    ), 200
