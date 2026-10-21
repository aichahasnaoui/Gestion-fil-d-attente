from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from ..extensions import db
from ..models import User, PatientProfile, ServiceAdminProfile

users_bp = Blueprint('users', __name__)


@users_bp.get('/users/me')
@jwt_required()
def get_me():
    user = User.query.get_or_404(int(get_jwt_identity()))
    data = user.to_dict()
    if user.role == 'patient' and user.patient_profile:
        data['patient_profile'] = user.patient_profile.to_dict()
    if user.role == 'doctor' and user.doctor_profile:
        data['doctor_profile'] = user.doctor_profile.to_dict()
    if user.role == 'service_admin':
        p = ServiceAdminProfile.query.filter_by(user_id=user.id).first()
        if p:
            data['service_admin_profile'] = p.to_dict()
    return jsonify(user=data), 200


@users_bp.patch('/users/me')
@jwt_required()
def update_me():
    user = User.query.get_or_404(int(get_jwt_identity()))
    d = request.get_json()
    for field in ['full_name', 'avatar_url', 'fcm_token']:
        if field in d:
            setattr(user, field, d[field])
    db.session.commit()
    return jsonify(user=user.to_dict()), 200


@users_bp.put('/users/me/patient-profile')
@jwt_required()
def upsert_patient_profile():
    user = User.query.get_or_404(int(get_jwt_identity()))
    if user.role != 'patient':
        return jsonify(error='Not a patient'), 403
    d = request.get_json()
    p = user.patient_profile or PatientProfile(user_id=user.id)
    for field in ['date_of_birth', 'gender', 'blood_type', 'allergies',
                  'chronic_conditions', 'emergency_contact_name',
                  'emergency_contact_phone', 'national_id']:
        if field in d:
            setattr(p, field, d[field])
    db.session.add(p)
    db.session.commit()
    return jsonify(profile=p.to_dict()), 200


@users_bp.patch('/users/me/doctor-profile')
@jwt_required()
def update_doctor_profile():
    user = User.query.get_or_404(int(get_jwt_identity()))
    if user.role != 'doctor' or not user.doctor_profile:
        return jsonify(error='Not a doctor'), 403
    d = request.get_json()
    doc = user.doctor_profile
    for field in ['specialty', 'bio', 'consultation_minutes', 'is_accepting', 'available_days']:
        if field in d:
            setattr(doc, field, d[field])
    db.session.commit()
    return jsonify(doctor=doc.to_dict()), 200
