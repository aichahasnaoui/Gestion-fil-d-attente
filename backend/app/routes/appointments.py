from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from sqlalchemy.orm import joinedload
from ..extensions import db, socketio
from ..models import Appointment, DoctorProfile, Notification, User

appointments_bp = Blueprint('appointments', __name__)

def _notify(user_id, ntype, title, body, data=None):
    n = Notification(user_id=user_id, type=ntype, title=title, body=body, data=data)
    db.session.add(n)
    db.session.flush()
    socketio.emit('notification', n.to_dict(), room=f'user_{user_id}')


@appointments_bp.post('/appointments')
@jwt_required()
def book_appointment():
    uid = int(get_jwt_identity())
    d = request.get_json()
    doctor = DoctorProfile.query.get_or_404(d['doctor_id'])
    if not doctor.is_accepting:
        return jsonify(error='Ce médecin n\'accepte pas de rendez-vous pour le moment.'), 400

    scheduled_str = d['scheduled_at'].replace('Z', '+00:00')
    try:
        scheduled_dt = datetime.fromisoformat(scheduled_str)
        if scheduled_dt.tzinfo is not None:
            scheduled_dt = datetime(*scheduled_dt.utctimetuple()[:6])
    except ValueError:
        scheduled_dt = datetime.strptime(d['scheduled_at'][:19], '%Y-%m-%dT%H:%M:%S')

    # Check if requested time is in the past
    if scheduled_dt < datetime.utcnow():
        return jsonify(error='Impossible de réserver un rendez-vous dans le passé.'), 400

    # Check doctor conflict: any active appointment within consultation window
    consult_minutes = doctor.consultation_minutes or 20
    conflict = Appointment.query.filter(
        Appointment.doctor_id == doctor.id,
        Appointment.status.in_(['pending', 'accepted', 'confirmed']),
        Appointment.scheduled_at >= scheduled_dt - timedelta(minutes=consult_minutes),
        Appointment.scheduled_at <= scheduled_dt + timedelta(minutes=consult_minutes),
    ).first()

    if conflict:
        # Convert conflict time to local (UTC+1)
        local_time = conflict.scheduled_at + timedelta(hours=1)
        time_str = local_time.strftime('%H:%M')
        date_str = local_time.strftime('%d/%m/%Y')
        return jsonify(
            error=f'Le médecin a déjà un rendez-vous le {date_str} à {time_str}. '
                  f'Veuillez choisir un autre créneau (au moins {consult_minutes} min d\'écart).'
        ), 409

    # Check patient doesn't already have appointment with same doctor on same day
    same_day_start = scheduled_dt.replace(hour=0, minute=0, second=0)
    same_day_end   = scheduled_dt.replace(hour=23, minute=59, second=59)
    patient_conflict = Appointment.query.filter(
        Appointment.patient_id == uid,
        Appointment.doctor_id == doctor.id,
        Appointment.status.in_(['pending', 'accepted', 'confirmed']),
        Appointment.scheduled_at >= same_day_start,
        Appointment.scheduled_at <= same_day_end,
    ).first()

    if patient_conflict:
        return jsonify(error='Vous avez déjà un rendez-vous avec ce médecin ce jour-là.'), 409

    appt = Appointment(
        patient_id=uid, doctor_id=doctor.id,
        scheduled_at=scheduled_dt,
        reason=d.get('reason'),
        duration_minutes=consult_minutes,
    )
    db.session.add(appt)
    db.session.flush()

    patient = User.query.get(uid)
    _notify(doctor.user_id, 'appointment_alert', 'New appointment request',
            f'{patient.full_name} requested an appointment on {d["scheduled_at"][:10]}',
            {'appointment_id': appt.id})
    db.session.commit()
    # Reload with relationships to get doctor name in response
    appt = Appointment.query\
        .options(joinedload(Appointment.doctor).joinedload(DoctorProfile.user))\
        .get(appt.id)
    return jsonify(appointment=appt.to_dict()), 201


@appointments_bp.get('/appointments/my')
@jwt_required()
def my_appointments():
    uid = int(get_jwt_identity())
    user = User.query.get(uid)
    if user.role == 'doctor':
        appts = Appointment.query\
            .options(joinedload(Appointment.doctor).joinedload(DoctorProfile.user))\
            .filter_by(doctor_id=user.doctor_profile.id)\
            .order_by(Appointment.scheduled_at.desc()).all()
    else:
        appts = Appointment.query\
            .options(joinedload(Appointment.doctor).joinedload(DoctorProfile.user))\
            .filter_by(patient_id=uid)\
            .order_by(Appointment.scheduled_at.desc()).all()
    return jsonify(appointments=[a.to_dict() for a in appts]), 200


@appointments_bp.patch('/appointments/<int:aid>/status')
@jwt_required()
def update_status(aid):
    uid = int(get_jwt_identity())
    appt = Appointment.query.get_or_404(aid)
    user = User.query.get(uid)
    if user.role != 'doctor' or appt.doctor.user_id != uid:
        return jsonify(error='Forbidden'), 403

    d = request.get_json()
    new_status = d.get('status')
    allowed = ['accepted', 'rejected', 'completed']
    if new_status not in allowed:
        return jsonify(error='Invalid status'), 400

    appt.status = new_status
    appt.doctor_notes = d.get('notes', appt.doctor_notes)
    appt.updated_at = datetime.utcnow()

    # Notify patient
    msgs = {
        'accepted':  ('Appointment Accepted ✅', 'Your appointment has been accepted by the doctor.'),
        'rejected':  ('Appointment Rejected ❌', 'Your appointment was declined. Please try another slot.'),
        'completed': ('Appointment Completed', 'Your appointment is marked as completed.'),
    }
    title, body = msgs[new_status]
    _notify(appt.patient_id, 'doctor_response', title, body, {'appointment_id': appt.id})
    db.session.commit()
    return jsonify(appointment=appt.to_dict()), 200


@appointments_bp.post('/appointments/<int:aid>/confirm')
@jwt_required()
def confirm_appointment(aid):
    uid = int(get_jwt_identity())
    appt = Appointment.query.get_or_404(aid)
    if appt.patient_id != uid:
        return jsonify(error='Forbidden'), 403
    if appt.status != 'accepted':
        return jsonify(error='Appointment not accepted yet'), 400
    if appt.confirmation_count >= 3:
        return jsonify(error='Already confirmed 3 times'), 400

    appt.confirmation_count += 1
    if appt.confirmation_count == 3:
        appt.status = 'confirmed'
        _notify(appt.doctor.user_id, 'appointment_alert', 'Patient confirmed arrival',
                f'Patient confirmed they will arrive for the appointment.',
                {'appointment_id': appt.id})
    db.session.commit()
    return jsonify(appointment=appt.to_dict(),
                   confirmations_left=3 - appt.confirmation_count), 200


@appointments_bp.post('/appointments/expire-past')
@jwt_required()
def expire_past():
    """Mark all past pending/accepted/confirmed appointments as expired."""
    uid = int(get_jwt_identity())
    now = datetime.utcnow()
    updated = Appointment.query.filter(
        Appointment.patient_id == uid,
        Appointment.scheduled_at < now,
        Appointment.status.in_(['pending', 'accepted', 'confirmed'])
    ).all()
    for a in updated:
        a.status = 'expired'
        a.updated_at = now
    db.session.commit()
    return jsonify(expired=[a.id for a in updated]), 200


@appointments_bp.post('/appointments/<int:aid>/attended')
@jwt_required()
def mark_attended(aid):
    uid = int(get_jwt_identity())
    appt = Appointment.query.get_or_404(aid)
    if appt.patient_id != uid:
        return jsonify(error='Forbidden'), 403
    if appt.status != 'expired':
        return jsonify(error='Appointment not expired'), 400
    appt.status = 'completed'
    appt.updated_at = datetime.utcnow()
    db.session.commit()
    return jsonify(appointment=appt.to_dict()), 200


@appointments_bp.post('/appointments/<int:aid>/cancel')
@jwt_required()
def cancel_appointment(aid):
    uid = int(get_jwt_identity())
    appt = Appointment.query.get_or_404(aid)
    user = User.query.get(uid)

    is_patient = appt.patient_id == uid
    is_doctor  = user.role == 'doctor' and appt.doctor.user_id == uid
    if not (is_patient or is_doctor):
        return jsonify(error='Forbidden'), 403
    if appt.status in ['completed', 'cancelled']:
        return jsonify(error='Cannot cancel'), 400

    appt.status = 'cancelled'
    data = request.get_json(silent=True, force=True) or {}
    appt.cancel_reason = data.get('reason', '')
    appt.updated_at = datetime.utcnow()

    notify_id = appt.doctor.user_id if is_patient else appt.patient_id
    _notify(notify_id, 'appointment_alert', 'Appointment Cancelled',
            'An appointment has been cancelled.', {'appointment_id': appt.id})
    db.session.commit()
    return jsonify(message='Appointment cancelled'), 200
