from flask import Blueprint, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from ..extensions import db
from ..models import Notification

notifications_bp = Blueprint('notifications', __name__)

@notifications_bp.get('/notifications')
@jwt_required()
def get_notifications():
    uid = int(get_jwt_identity())
    notifs = Notification.query.filter_by(user_id=uid)\
        .order_by(Notification.sent_at.desc()).limit(50).all()
    unread = Notification.query.filter_by(user_id=uid, is_read=False).count()
    return jsonify(notifications=[n.to_dict() for n in notifs], unread=unread), 200


@notifications_bp.patch('/notifications/<int:nid>/read')
@jwt_required()
def read_notification(nid):
    uid = int(get_jwt_identity())
    n = Notification.query.get_or_404(nid)
    if n.user_id != uid:
        return jsonify(error='Forbidden'), 403
    n.is_read = True
    db.session.commit()
    return jsonify(message='Marked as read'), 200


@notifications_bp.post('/notifications/read-all')
@jwt_required()
def read_all():
    uid = int(get_jwt_identity())
    Notification.query.filter_by(user_id=uid, is_read=False).update({'is_read': True})
    db.session.commit()
    return jsonify(message='All marked as read'), 200
