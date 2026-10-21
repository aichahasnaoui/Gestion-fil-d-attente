import traceback
try:
    from app import create_app
    from app.extensions import db
    from app.models import DoctorProfile, User

    app = create_app()
    ctx = app.app_context()
    ctx.push()

    p = DoctorProfile.query.get(18)
    print('Profile found:', p)
    if p:
        print('  user_id:', p.user_id)
        print('  user:', p.user)
        if p.user:
            print('  user.full_name:', p.user.full_name)
            print('  user.is_active:', p.user.is_active)
        print('  is_accepting:', p.is_accepting)
        print('  specialty:', p.specialty)

    print()
    q = DoctorProfile.query.join(DoctorProfile.user).filter(User.is_active == True)
    results = q.all()
    print('API query result count:', len(results))
    for d in results:
        print(f'  -> {d.user.full_name} specialty={d.specialty}')

except Exception as e:
    traceback.print_exc()
