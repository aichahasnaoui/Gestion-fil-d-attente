from app import create_app
from app.extensions import db, bcrypt
from app.models import User, DoctorProfile, Service

app = create_app()

DOCTORS = [
    {'name': 'Afef Zitouni', 'spec': 'Gynecology', 'email': 'afef.zitouni@test.com', 'phone': '20111222'},
    {'name': 'Afef Farah', 'spec': 'Rheumatology', 'email': 'afef.farah@test.com', 'phone': '20111333'},
    {'name': 'Ali Ayadi', 'spec': 'ENT', 'email': 'ali.ayadi@test.com', 'phone': '20111444'},
    {'name': 'Mohamed Mourad Ben Khalifa', 'spec': 'Ophthalmology', 'email': 'mohamed.benkhalifa@test.com', 'phone': '20111555'},
    {'name': 'Abdelghani Boudis', 'spec': 'Ophthalmology', 'email': 'abdelghani.boudis@test.com', 'phone': '20111666'},
]

with app.app_context():
    hospital = Service.query.filter_by(name='Hopital Charles Nicolle').first()
    sid = hospital.id if hospital else None

    for d in DOCTORS:
        if User.query.filter_by(email=d['email']).first():
            print(f"[SKIP] {d['name']} already exists.")
            continue
            
        user = User(
            full_name=d['name'],
            email=d['email'],
            phone=d['phone'],
            password_hash=bcrypt.generate_password_hash('doctor123').decode(),
            role='doctor',
            is_verified=True,
            is_active=True
        )
        db.session.add(user)
        try:
            db.session.flush()
        except Exception as e:
            db.session.rollback()
            print(f"[ERROR] Could not add {d['name']}: {e}")
            continue
        
        profile = DoctorProfile(
            user_id=user.id,
            service_id=sid,
            specialty=d['spec'],
            bio=f"Specialist in {d['spec']}",
            consultation_minutes=20,
            is_accepting=True
        )
        db.session.add(profile)
        print(f"[OK] Added {d['name']} ({d['spec']})")

    db.session.commit()
