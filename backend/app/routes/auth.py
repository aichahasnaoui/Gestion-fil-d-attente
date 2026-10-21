import random, string
from datetime import datetime, timedelta, timezone
from flask import Blueprint, request, jsonify
from flask_jwt_extended import create_access_token, create_refresh_token, jwt_required, get_jwt_identity
from ..extensions import db, bcrypt
from ..models import User, OtpCode, PatientProfile, DoctorProfile, ServiceAdminProfile

auth_bp = Blueprint('auth', __name__)

def _gen_otp():
    return ''.join(random.choices(string.digits, k=6))

@auth_bp.post('/auth/register')
def register():
    d = request.get_json()
    if not d:
        print("Error: Invalid JSON received for registration")
        return jsonify(error='Invalid JSON'), 400
    required = ['full_name', 'email', 'phone', 'password', 'role']
    if not all(k in d for k in required):
        print(f"Error: Missing fields for registration. Received: {d}")
        return jsonify(error='Missing fields'), 400

    if User.query.filter((User.email == d['email']) | (User.phone == d['phone'])).first():
        print(f"Error: Email {d['email']} or phone {d['phone']} already exists.")
        return jsonify(error='Email or phone already exists'), 409

    allowed_roles = ['patient', 'client', 'doctor', 'service_admin']
    if d['role'] not in allowed_roles:
        print(f"Error: Invalid role '{d['role']}' provided for registration.")
        return jsonify(error='Invalid role'), 400

    user = User(
        full_name=d['full_name'], email=d['email'], phone=d['phone'],
        password_hash=bcrypt.generate_password_hash(d['password']).decode(),
        role=d['role'],
        is_verified=True,
    )
    db.session.add(user)
    db.session.flush()

    # Create role-specific profile
    if d['role'] == 'patient':
        db.session.add(PatientProfile(user_id=user.id))
    elif d['role'] == 'doctor':
        specialty = d.get('specialty', 'General Medicine')
        service_id = d.get('service_id')
        db.session.add(DoctorProfile(
            user_id=user.id, specialty=specialty,
            bio=d.get('bio', ''),
            consultation_minutes=int(d.get('consultation_minutes', 20)),
            is_accepting=True, service_id=service_id,
        ))
    elif d['role'] == 'service_admin':
        service_id = d.get('service_id')
        if service_id:
            db.session.add(ServiceAdminProfile(user_id=user.id, service_id=int(service_id)))

    # OTP
    otp = OtpCode(user_id=user.id, code=_gen_otp(), purpose='verify',
                  expires_at=datetime.now(timezone.utc) + timedelta(minutes=10))
    db.session.add(otp)

    try:
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        print(f"Error during user registration: {e}")
        return jsonify(error=f'Account creation failed: {str(e)}'), 500

    # Auto-login after register
    access  = create_access_token(identity=str(user.id), additional_claims={'role': user.role})
    refresh = create_refresh_token(identity=str(user.id))

    print(f"User {user.email} registered successfully.")
    return jsonify(
        user_id=user.id,
        access_token=access,
        refresh_token=refresh,
        user=user.to_dict(),
        otp_code=otp.code,
        message='Registration successful.'
    ), 201


@auth_bp.post('/auth/verify-otp')
def verify_otp():
    d = request.get_json()
    otp = OtpCode.query.filter_by(
        user_id=d['user_id'], code=d['code'], purpose='verify', is_used=False
    ).first()
    if not otp or otp.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        return jsonify(error='Invalid or expired OTP'), 400
    otp.is_used = True
    User.query.filter_by(id=d['user_id']).update({'is_verified': True})
    db.session.commit()
    return jsonify(message='Account verified'), 200


@auth_bp.post('/auth/login')
def login():
    d = request.get_json()
    if not d:
        return jsonify(error='Invalid JSON'), 400
    ident = d.get('email_or_phone', '')
    user = User.query.filter(
        (User.email == ident) | (User.phone == ident)
    ).first()
    if not user or not bcrypt.check_password_hash(user.password_hash, d.get('password', '')):
        return jsonify(error='Invalid credentials'), 401
    if not user.is_verified:
        return jsonify(error='Account not verified'), 403
    if not user.is_active:
        return jsonify(error='Account disabled'), 403

    user.last_login_at = datetime.now(timezone.utc)
    db.session.commit()

    access  = create_access_token(identity=str(user.id), additional_claims={'role': user.role})
    refresh = create_refresh_token(identity=str(user.id))
    return jsonify(access_token=access, refresh_token=refresh, user=user.to_dict()), 200


@auth_bp.post('/auth/refresh')
@jwt_required(refresh=True)
def refresh():
    uid = get_jwt_identity()
    user = User.query.get(int(uid))
    access = create_access_token(identity=uid, additional_claims={'role': user.role})
    return jsonify(access_token=access), 200


@auth_bp.post('/auth/forgot-password')
def forgot_password():
    phone = request.get_json().get('phone')
    user = User.query.filter_by(phone=phone).first()
    if not user:
        return jsonify(error='User not found'), 404
    otp = OtpCode(user_id=user.id, code=_gen_otp(), purpose='reset',
                  expires_at=datetime.now(timezone.utc) + timedelta(minutes=10))
    db.session.add(otp)
    db.session.commit()
    return jsonify(user_id=user.id, otp_code=otp.code, message='Reset OTP sent'), 200


@auth_bp.post('/auth/reset-password')
def reset_password():
    d = request.get_json()
    otp = OtpCode.query.filter_by(
        user_id=d['user_id'], code=d['code'], purpose='reset', is_used=False
    ).first()
    if not otp or otp.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        return jsonify(error='Invalid or expired OTP'), 400
    otp.is_used = True
    user = User.query.get(d['user_id'])
    user.password_hash = bcrypt.generate_password_hash(d['new_password']).decode()
    db.session.commit()
    return jsonify(message='Password reset successful'), 200
