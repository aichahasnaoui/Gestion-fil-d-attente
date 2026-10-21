from datetime import datetime
from .extensions import db

class User(db.Model):
    __tablename__ = 'users'
    id            = db.Column(db.Integer, primary_key=True)
    full_name     = db.Column(db.String(120), nullable=False)
    email         = db.Column(db.String(120), unique=True, nullable=False)
    phone         = db.Column(db.String(20), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    role          = db.Column(db.String(20), nullable=False, default='client')  # patient|client|doctor|assistant|admin
    avatar_url    = db.Column(db.String(300))
    is_verified   = db.Column(db.Boolean, default=False)
    is_active     = db.Column(db.Boolean, default=True)
    fcm_token     = db.Column(db.String(300))
    created_at    = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at    = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    last_login_at = db.Column(db.DateTime)

    patient_profile   = db.relationship('PatientProfile', backref='user', uselist=False)
    doctor_profile    = db.relationship('DoctorProfile',  backref='user', uselist=False)
    tickets           = db.relationship('Ticket', backref='user', lazy='dynamic')
    appointments      = db.relationship('Appointment', foreign_keys='Appointment.patient_id', backref='patient', lazy='dynamic')
    records           = db.relationship('MedicalRecord', backref='patient', lazy='dynamic')
    notifications     = db.relationship('Notification', backref='user', lazy='dynamic')
    prescriptions_as_patient = db.relationship('Prescription', foreign_keys='Prescription.patient_id', lazy='dynamic')

    def __init__(self, **kwargs):
        super(User, self).__init__(**kwargs)

    def to_dict(self):
        return {
            'id': self.id, 'full_name': self.full_name, 'email': self.email,
            'phone': self.phone, 'role': self.role, 'avatar_url': self.avatar_url,
            'is_verified': self.is_verified, 'is_active': self.is_active,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }


class PatientProfile(db.Model):
    __tablename__ = 'patient_profiles'
    id                      = db.Column(db.Integer, primary_key=True)
    user_id                 = db.Column(db.Integer, db.ForeignKey('users.id'), unique=True, nullable=False)
    date_of_birth           = db.Column(db.Date)
    gender                  = db.Column(db.String(10))
    blood_type              = db.Column(db.String(5))
    allergies               = db.Column(db.ARRAY(db.String))
    chronic_conditions      = db.Column(db.ARRAY(db.String))
    emergency_contact_name  = db.Column(db.String(120))
    emergency_contact_phone = db.Column(db.String(20))
    national_id             = db.Column(db.String(30))

    def to_dict(self):
        return {
            'user_id': self.user_id, 'date_of_birth': str(self.date_of_birth) if self.date_of_birth else None,
            'gender': self.gender, 'blood_type': self.blood_type,
            'allergies': self.allergies or [], 'chronic_conditions': self.chronic_conditions or [],
            'emergency_contact_name': self.emergency_contact_name,
            'emergency_contact_phone': self.emergency_contact_phone,
        }


class Service(db.Model):
    __tablename__ = 'services'
    id               = db.Column(db.Integer, primary_key=True)
    name             = db.Column(db.String(150), nullable=False)
    type             = db.Column(db.String(30), nullable=False)  # bank|post|telecom|cnss|hospital|clinic|other
    address          = db.Column(db.String(300))
    wilaya           = db.Column(db.String(60))
    logo_url         = db.Column(db.String(300))
    is_active        = db.Column(db.Boolean, default=True)
    opens_at         = db.Column(db.Time)
    closes_at        = db.Column(db.Time)
    max_daily_tickets = db.Column(db.Integer, default=200)
    created_at       = db.Column(db.DateTime, default=datetime.utcnow)

    queues   = db.relationship('Queue', backref='service', lazy='dynamic')
    doctors  = db.relationship('DoctorProfile', backref='service', lazy='dynamic')

    def to_dict(self, today_stats=None):
        d = {
            'id': self.id, 'name': self.name, 'type': self.type,
            'address': self.address, 'wilaya': self.wilaya, 'logo_url': self.logo_url,
            'is_active': self.is_active,
            'max_daily_tickets': self.max_daily_tickets or 200,
            'today_in_queue': 0, 'today_avg_wait': 0,
            'today_total_issued': 0,
        }
        if today_stats:
            d.update(today_stats)
        return d


class DoctorProfile(db.Model):
    __tablename__ = 'doctor_profiles'
    id                       = db.Column(db.Integer, primary_key=True)
    user_id                  = db.Column(db.Integer, db.ForeignKey('users.id'), unique=True, nullable=False)
    service_id               = db.Column(db.Integer, db.ForeignKey('services.id'))
    specialty                = db.Column(db.String(100), nullable=False)
    bio                      = db.Column(db.Text)
    license_number           = db.Column(db.String(50))
    consultation_minutes     = db.Column(db.Integer, default=20)
    is_accepting             = db.Column(db.Boolean, default=True)
    available_days           = db.Column(db.JSON)  # {"mon":["09:00","17:00"],...}

    appointments = db.relationship('Appointment', foreign_keys='Appointment.doctor_id', backref='doctor', lazy='dynamic')

    def to_dict(self):
        return {
            'id': self.id, 'user_id': self.user_id, 'service_id': self.service_id,
            'specialty': self.specialty, 'bio': self.bio,
            'consultation_minutes': self.consultation_minutes,
            'is_accepting': self.is_accepting,
            'available_days': self.available_days,
            'user': self.user.to_dict() if self.user else None,
        }


class ServiceAdminProfile(db.Model):
    __tablename__ = 'service_admin_profiles'
    id         = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey('users.id'), unique=True, nullable=False)
    service_id = db.Column(db.Integer, db.ForeignKey('services.id'), nullable=False)
    assigned_at = db.Column(db.DateTime, default=datetime.utcnow)

    user    = db.relationship('User', backref=db.backref('service_admin_profile', uselist=False))
    service = db.relationship('Service', backref=db.backref('admins', lazy='dynamic'))

    def to_dict(self):
        return {'service_id': self.service_id, 'user_id': self.user_id}


class Guichet(db.Model):
    __tablename__ = 'guichets'
    id         = db.Column(db.Integer, primary_key=True)
    service_id = db.Column(db.Integer, db.ForeignKey('services.id'), nullable=False)
    name       = db.Column(db.String(60), nullable=False)  # ex: 'Guichet 1'
    is_open    = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    service = db.relationship('Service', backref=db.backref('guichets', lazy='dynamic'))

    def to_dict(self):
        return {
            'id': self.id, 'service_id': self.service_id,
            'name': self.name, 'is_open': self.is_open,
        }


class Queue(db.Model):
    __tablename__ = 'queues'
    id              = db.Column(db.Integer, primary_key=True)
    service_id      = db.Column(db.Integer, db.ForeignKey('services.id'), nullable=False)
    date            = db.Column(db.Date, nullable=False, default=datetime.utcnow)
    current_number  = db.Column(db.Integer, default=0)
    total_issued    = db.Column(db.Integer, default=0)
    is_open         = db.Column(db.Boolean, default=True)
    avg_wait_minutes = db.Column(db.Integer, default=10)

    tickets = db.relationship('Ticket', backref='queue', lazy='dynamic')

    __table_args__ = (db.UniqueConstraint('service_id', 'date', name='uq_service_date'),)


class Ticket(db.Model):
    __tablename__ = 'tickets'
    id                 = db.Column(db.Integer, primary_key=True)
    queue_id           = db.Column(db.Integer, db.ForeignKey('queues.id'), nullable=False)
    user_id            = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    ticket_number      = db.Column(db.Integer, nullable=False)
    status             = db.Column(db.String(20), default='waiting')  # waiting|called|confirmed|served|cancelled|no_show
    qr_code            = db.Column(db.String(100), unique=True)
    confirmation_count = db.Column(db.Integer, default=0)
    issued_at          = db.Column(db.DateTime, default=datetime.utcnow)
    called_at          = db.Column(db.DateTime)
    served_at          = db.Column(db.DateTime)
    cancelled_at       = db.Column(db.DateTime)
    estimated_wait_min = db.Column(db.Integer)
    cancel_reason      = db.Column(db.String(200))

    def to_dict(self, ahead=0):
        estimated_wait = self.estimated_wait_min
        if self.status in ['waiting', 'called', 'confirmed'] and self.queue:
            try:
                open_guichets = Guichet.query.filter_by(
                    service_id=self.queue.service_id, is_open=True
                ).count()
            except Exception:
                open_guichets = 1
            if open_guichets <= 0:
                open_guichets = 1
            base = 5
            estimated_wait = max(1, ((ahead + 1) * base) // open_guichets)
        return {
            'id': self.id, 'queue_id': self.queue_id, 'user_id': self.user_id,
            'service_id': self.queue.service_id if self.queue else 0,
            'service_name': self.queue.service.name if (self.queue and self.queue.service) else '',
            'service_logo': self.queue.service.logo_url if (self.queue and self.queue.service) else None,
            'ticket_number': self.ticket_number, 'status': self.status,
            'qr_code': self.qr_code, 'issued_at': self.issued_at.isoformat() if self.issued_at else None,
            'confirmation_count': self.confirmation_count,
            'estimated_wait_min': estimated_wait,
            'ahead': ahead,
        }


class Appointment(db.Model):
    __tablename__ = 'appointments'
    id                 = db.Column(db.Integer, primary_key=True)
    patient_id         = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    doctor_id          = db.Column(db.Integer, db.ForeignKey('doctor_profiles.id'), nullable=False)
    scheduled_at       = db.Column(db.DateTime, nullable=False)
    duration_minutes   = db.Column(db.Integer, default=20)
    status             = db.Column(db.String(20), default='pending')  # pending|accepted|rejected|confirmed|completed|cancelled|no_show|expired
    reason             = db.Column(db.Text)
    doctor_notes       = db.Column(db.Text)
    confirmation_count = db.Column(db.Integer, default=0)
    cancel_reason      = db.Column(db.String(200))
    created_at         = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at         = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id, 'patient_id': self.patient_id, 'doctor_id': self.doctor_id,
            'patient_name': self.patient.full_name if self.patient else 'Unknown',
            'doctor_name': self.doctor.user.full_name if self.doctor and self.doctor.user else 'Unknown',
            'doctor_specialty': self.doctor.specialty if self.doctor else '',
            'scheduled_at': self.scheduled_at.isoformat() if self.scheduled_at else None,
            'duration_minutes': self.duration_minutes, 'status': self.status,
            'reason': self.reason, 'doctor_notes': self.doctor_notes,
            'confirmation_count': self.confirmation_count,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }


class MedicalRecord(db.Model):
    __tablename__ = 'medical_records'
    id                    = db.Column(db.Integer, primary_key=True)
    patient_id            = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    record_type           = db.Column(db.String(30), nullable=False)  # image|analysis|prescription|report|other
    title                 = db.Column(db.String(200), nullable=False)
    file_url              = db.Column(db.String(300), nullable=False)
    file_type             = db.Column(db.String(50))
    file_size             = db.Column(db.Integer)
    notes                 = db.Column(db.Text)
    is_shared_with_doctor = db.Column(db.Boolean, default=False)
    shared_with_doctor_id = db.Column(db.Integer, db.ForeignKey('doctor_profiles.id'))
    uploaded_at           = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id, 'patient_id': self.patient_id, 'record_type': self.record_type,
            'title': self.title, 'file_url': self.file_url, 'file_type': self.file_type,
            'notes': self.notes, 'is_shared_with_doctor': self.is_shared_with_doctor,
            'shared_with_doctor_id': self.shared_with_doctor_id,
            'uploaded_at': self.uploaded_at.isoformat() if self.uploaded_at else None,
        }


class Prescription(db.Model):
    __tablename__ = 'prescriptions'
    id             = db.Column(db.Integer, primary_key=True)
    appointment_id = db.Column(db.Integer, db.ForeignKey('appointments.id'), nullable=False)
    doctor_id      = db.Column(db.Integer, db.ForeignKey('doctor_profiles.id'), nullable=False)
    patient_id     = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    medications    = db.Column(db.JSON)  # [{name, dose, frequency, duration}]
    instructions   = db.Column(db.Text)
    is_active      = db.Column(db.Boolean, default=True)
    created_at     = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        patient_name = 'Unknown'
        try:
            from .models import User as _User
            p = _User.query.get(self.patient_id)
            if p:
                patient_name = p.full_name
        except Exception:
            pass
        return {
            'id': self.id, 'appointment_id': self.appointment_id,
            'doctor_id': self.doctor_id, 'patient_id': self.patient_id,
            'patient_name': patient_name,
            'medications': self.medications, 'instructions': self.instructions,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }


class Notification(db.Model):
    __tablename__ = 'notifications'
    id         = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    type       = db.Column(db.String(40), nullable=False)  # ticket_alert|appointment_alert|confirmation_request|system|doctor_response
    title      = db.Column(db.String(200), nullable=False)
    body       = db.Column(db.Text, nullable=False)
    data       = db.Column(db.JSON)
    is_read    = db.Column(db.Boolean, default=False)
    sent_at    = db.Column(db.DateTime, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime)

    def to_dict(self):
        return {
            'id': self.id, 'user_id': self.user_id, 'type': self.type,
            'title': self.title, 'body': self.body, 'data': self.data,
            'is_read': self.is_read,
            'sent_at': self.sent_at.isoformat() if self.sent_at else None,
        }


class Conversation(db.Model):
    __tablename__ = 'conversations'
    id         = db.Column(db.Integer, primary_key=True)
    patient_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    doctor_id  = db.Column(db.Integer, db.ForeignKey('doctor_profiles.id'), nullable=False)
    record_id  = db.Column(db.Integer, db.ForeignKey('medical_records.id'))
    subject    = db.Column(db.String(200), nullable=False, default='Dossier medical')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    patient = db.relationship('User', foreign_keys=[patient_id])
    doctor = db.relationship('DoctorProfile', foreign_keys=[doctor_id])
    record = db.relationship('MedicalRecord', foreign_keys=[record_id])

    def to_dict(self):
        last = Message.query.filter_by(conversation_id=self.id)\
            .order_by(Message.created_at.desc()).first()
        return {
            'id': self.id,
            'patient_id': self.patient_id,
            'patient_name': self.patient.full_name if self.patient else '',
            'doctor_id': self.doctor_id,
            'doctor_name': self.doctor.user.full_name if self.doctor and self.doctor.user else '',
            'record_id': self.record_id,
            'record_title': self.record.title if self.record else None,
            'subject': self.subject,
            'last_message': last.body if last else '',
            'last_message_at': last.created_at.isoformat() if last else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }


class Message(db.Model):
    __tablename__ = 'messages'
    id              = db.Column(db.Integer, primary_key=True)
    conversation_id = db.Column(db.Integer, db.ForeignKey('conversations.id'), nullable=False)
    sender_id       = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    body            = db.Column(db.Text, nullable=False)
    attachment_url  = db.Column(db.String(300))
    attachment_type = db.Column(db.String(50))
    attachment_name = db.Column(db.String(200))
    created_at      = db.Column(db.DateTime, default=datetime.utcnow)
    read_at         = db.Column(db.DateTime)

    conversation = db.relationship('Conversation', foreign_keys=[conversation_id])
    sender       = db.relationship('User', foreign_keys=[sender_id])

    def to_dict(self):
        return {
            'id': self.id,
            'conversation_id': self.conversation_id,
            'sender_id': self.sender_id,
            'sender_name': self.sender.full_name if self.sender else '',
            'body': self.body,
            'attachment_url': self.attachment_url,
            'attachment_type': self.attachment_type,
            'attachment_name': self.attachment_name,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'read_at': self.read_at.isoformat() if self.read_at else None,
        }


class OtpCode(db.Model):
    __tablename__ = 'otp_codes'
    id         = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    code       = db.Column(db.String(6), nullable=False)
    purpose    = db.Column(db.String(20), default='verify')  # verify|reset
    expires_at = db.Column(db.DateTime, nullable=False)
    is_used    = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
