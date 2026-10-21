import traceback
try:
    from app import create_app
    from app.extensions import db
    from app.models import User, DoctorProfile

    app = create_app()
    ctx = app.app_context()
    ctx.push()

    doctor_users = User.query.filter_by(role='doctor').all()
    print('Doctor users found:', len(doctor_users))

    for u in doctor_users:
        print(f'  Checking {u.full_name} (id={u.id}), profile={u.doctor_profile}')
        if not u.doctor_profile:
            p = DoctorProfile(
                user_id=u.id,
                service_id=5,
                specialty='General Medicine',
                bio='',
                consultation_minutes=20,
                is_accepting=True,
            )
            db.session.add(p)
            db.session.commit()
            print(f'  -> Profile created id={p.id}')

    total = DoctorProfile.query.count()
    print('Total profiles:', total)

except Exception as e:
    traceback.print_exc()
