import traceback
try:
    from app import create_app
    from app.models import User
    app = create_app()
    ctx = app.app_context()
    ctx.push()
    users = User.query.all()
    for u in users:
        print(u.id, u.full_name, u.email, u.phone, u.role)
except Exception as e:
    traceback.print_exc()
