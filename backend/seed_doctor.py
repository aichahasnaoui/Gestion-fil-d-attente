"""
Verify doctors already in the database:
    cd backend
    python seed_doctor.py
"""
from app import create_app
from app.extensions import db
from app.models import DoctorProfile

app = create_app()
with app.app_context():
    doctors = DoctorProfile.query.all()
    if not doctors:
        print("[WARN] No doctors found in the database.")
    else:
        print(f"[OK] {len(doctors)} doctor(s) found:\n")
        for d in doctors:
            print(f"  - {d.user.full_name} | {d.specialty} | service_id={d.service_id} | accepting={d.is_accepting}")
