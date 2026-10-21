from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from ..extensions import db
from ..models import DoctorProfile, User, Appointment, Prescription, MedicalRecord

doctors_bp = Blueprint('doctors', __name__)

@doctors_bp.get('/doctors')
@jwt_required()
def list_doctors():
    q = DoctorProfile.query.join(DoctorProfile.user).filter(User.is_active == True)
    if s := request.args.get('specialty'):
        q = q.filter(DoctorProfile.specialty == s)
    if sid := request.args.get('service_id'):
        q = q.filter(DoctorProfile.service_id == int(sid))
    doctors = q.all()
    return jsonify(doctors=[d.to_dict() for d in doctors if d.user]), 200


@doctors_bp.get('/doctors/me/patients')
@jwt_required()
def my_patients():
    uid = int(get_jwt_identity())
    user = User.query.get_or_404(uid)
    if user.role != 'doctor':
        return jsonify(error='Forbidden'), 403
    doc = user.doctor_profile
    patient_ids = db.session.query(Appointment.patient_id).filter_by(
        doctor_id=doc.id
    ).filter(Appointment.status.in_(['accepted','confirmed','completed'])).distinct().all()
    patients = []
    for (pid,) in patient_ids:
        p = User.query.get(pid)
        if p:
            d = p.to_dict()
            if p.patient_profile:
                d.update(p.patient_profile.to_dict())
            patients.append(d)
    return jsonify(patients=patients), 200


@doctors_bp.patch('/doctors/me')
@jwt_required()
def update_doctor_profile():
    uid = int(get_jwt_identity())
    user = User.query.get_or_404(uid)
    if user.role != 'doctor':
        return jsonify(error='Forbidden'), 403
    d = request.get_json()
    doc = user.doctor_profile
    for field in ['specialty', 'bio', 'consultation_minutes', 'is_accepting', 'available_days']:
        if field in d:
            setattr(doc, field, d[field])
    db.session.commit()
    return jsonify(doctor=doc.to_dict()), 200


@doctors_bp.get('/prescriptions/my')
@jwt_required()
def my_prescriptions():
    uid = int(get_jwt_identity())
    user = User.query.get_or_404(uid)
    if user.role == 'doctor':
        prescs = Prescription.query.filter_by(doctor_id=user.doctor_profile.id).all()
    else:
        prescs = Prescription.query.filter_by(patient_id=uid).all()
    return jsonify(prescriptions=[p.to_dict() for p in prescs]), 200


@doctors_bp.post('/prescriptions')
@jwt_required()
def create_prescription():
    uid = int(get_jwt_identity())
    user = User.query.get_or_404(uid)
    if user.role != 'doctor':
        return jsonify(error='Forbidden'), 403
    d = request.get_json()
    appt = Appointment.query.get_or_404(d['appointment_id'])
    presc = Prescription(
        appointment_id=appt.id, doctor_id=user.doctor_profile.id,
        patient_id=appt.patient_id, medications=d.get('medications', []),
        instructions=d.get('instructions'),
    )
    db.session.add(presc)
    db.session.commit()
    return jsonify(prescription=presc.to_dict()), 201
