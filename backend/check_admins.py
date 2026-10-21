import traceback
try:
    from app import create_app
    from app.models import User, ServiceAdminProfile
    app = create_app()
    ctx = app.app_context()
    ctx.push()
    admins = User.query.filter_by(role='service_admin').all()
    print('Service admins:', len(admins))
    for u in admins:
        p = ServiceAdminProfile.query.filter_by(user_id=u.id).first()
        print(f'  id={u.id} name={u.full_name} email={u.email} service_id={p.service_id if p else None}')
except Exception as e:
    traceback.print_exc()
