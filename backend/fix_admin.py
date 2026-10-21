import traceback
try:
    from app import create_app
    from app.extensions import db
    from app.models import User, ServiceAdminProfile

    app = create_app()
    ctx = app.app_context()
    ctx.push()

    # Fix all service_admin users with no profile
    admins = User.query.filter_by(role='service_admin').all()
    for u in admins:
        p = ServiceAdminProfile.query.filter_by(user_id=u.id).first()
        if not p:
            # Create profile with service_id=1 as default
            new_p = ServiceAdminProfile(user_id=u.id, service_id=1)
            db.session.add(new_p)
            print(f'[FIXED] Created profile for {u.full_name} -> service_id=1')
        elif not p.service_id:
            p.service_id = 1
            print(f'[FIXED] Set service_id=1 for {u.full_name}')
        else:
            print(f'[OK] {u.full_name} -> service_id={p.service_id}')

    db.session.commit()
    print('Done.')

except Exception as e:
    traceback.print_exc()
