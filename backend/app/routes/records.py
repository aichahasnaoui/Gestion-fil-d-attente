import os, uuid
from flask import Blueprint, request, jsonify, current_app, send_from_directory
from flask_jwt_extended import jwt_required, get_jwt_identity
from ..extensions import db
from ..models import MedicalRecord, User, DoctorProfile

records_bp = Blueprint('records', __name__)

ALLOWED = {'png', 'jpg', 'jpeg', 'pdf', 'dcm', 'mp4', 'mov'}

def _allowed(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED


@records_bp.get('/uploads/<path:filename>')
def serve_upload(filename):
    folder = os.path.abspath(current_app.config['UPLOAD_FOLDER'])
    return send_from_directory(folder, filename)


@records_bp.post('/records/upload')
@jwt_required()
def upload_record():
    uid = int(get_jwt_identity())
    if 'file' not in request.files:
        return jsonify(error='No file provided'), 400
    f = request.files['file']
    if not f.filename or not _allowed(f.filename):
        return jsonify(error='File type not allowed. Use: png, jpg, pdf, dcm'), 400

    ext      = f.filename.rsplit('.', 1)[1].lower()
    filename = f'{uuid.uuid4()}.{ext}'
    folder   = os.path.abspath(current_app.config['UPLOAD_FOLDER'])
    os.makedirs(folder, exist_ok=True)
    filepath = os.path.join(folder, filename)
    f.save(filepath)

    record = MedicalRecord(
        patient_id=uid,
        record_type=request.form.get('record_type', 'other'),
        title=request.form.get('title') or f.filename,
        file_url=f'/api/uploads/{filename}',
        file_type=ext,
        notes=request.form.get('notes'),
    )
    db.session.add(record)
    db.session.commit()
    return jsonify(record=record.to_dict()), 201


@records_bp.get('/records/my')
@jwt_required()
def my_records():
    uid = int(get_jwt_identity())
    records = MedicalRecord.query.filter_by(patient_id=uid)\
        .order_by(MedicalRecord.uploaded_at.desc()).all()
    return jsonify(records=[r.to_dict() for r in records]), 200


@records_bp.delete('/records/<int:rid>')
@jwt_required()
def delete_record(rid):
    uid = int(get_jwt_identity())
    r = MedicalRecord.query.get_or_404(rid)
    if r.patient_id != uid:
        return jsonify(error='Forbidden'), 403
    db.session.delete(r)
    db.session.commit()
    return jsonify(message='Deleted'), 200


@records_bp.patch('/records/<int:rid>/share')
@jwt_required()
def share_record(rid):
    uid = int(get_jwt_identity())
    r = MedicalRecord.query.get_or_404(rid)
    if r.patient_id != uid:
        return jsonify(error='Forbidden'), 403
    d = request.get_json()
    r.is_shared_with_doctor = d.get('share', True)
    r.shared_with_doctor_id = d.get('doctor_id')
    db.session.commit()
    return jsonify(record=r.to_dict()), 200


@records_bp.get('/records/patient/<int:pid>')
@jwt_required()
def patient_records(pid):
    uid = int(get_jwt_identity())
    user = User.query.get_or_404(uid)
    if user.role not in ['doctor', 'assistant']:
        return jsonify(error='Forbidden'), 403
    records = MedicalRecord.query.filter_by(
        patient_id=pid, is_shared_with_doctor=True
    ).all()
    return jsonify(records=[r.to_dict() for r in records]), 200
