import traceback
try:
    from app import create_app
    from app.extensions import db, bcrypt
    from app.models import User, DoctorProfile, PatientProfile

    app = create_app()
    ctx = app.app_context()
    ctx.push()

    # Test patient registration
    with app.test_client() as c:
        res = c.post('/api/auth/register', json={
            'full_name': 'Test Patient',
            'email': 'testpatient999@test.com',
            'phone': '11111111',
            'password': 'test123',
            'role': 'patient',
        })
        print('Patient register status:', res.status_code)
        print('Patient register response:', res.get_json())

    # Cleanup
    u = User.query.filter_by(email='testpatient999@test.com').first()
    if u:
        if u.patient_profile:
            db.session.delete(u.patient_profile)
        db.session.delete(u)
        db.session.commit()

    # Test doctor registration
    with app.test_client() as c:
        res = c.post('/api/auth/register', json={
            'full_name': 'Test Doctor',
            'email': 'testdoctor999@test.com',
            'phone': '22222221',
            'password': 'test123',
            'role': 'doctor',
            'specialty': 'Cardiology',
            'consultation_minutes': 20,
            'bio': 'Test bio',
        })
        print('Doctor register status:', res.status_code)
        print('Doctor register response:', res.get_json())

    # Cleanup
    u = User.query.filter_by(email='testdoctor999@test.com').first()
    if u:
        if u.doctor_profile:
            db.session.delete(u.doctor_profile)
        db.session.delete(u)
        db.session.commit()

except Exception as e:
    traceback.print_exc()
