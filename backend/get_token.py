import traceback
try:
    from app import create_app
    from app.extensions import bcrypt
    from app.models import User
    from flask_jwt_extended import create_access_token

    app = create_app()
    ctx = app.app_context()
    ctx.push()

    # Reset patient password and get token
    u = User.query.filter_by(role='patient').first()
    u.password_hash = bcrypt.generate_password_hash('test123').decode()
    from app.extensions import db
    db.session.commit()
    print('Patient:', u.email, '/ phone:', u.phone, '/ new password: test123')

    token = create_access_token(identity=str(u.id), additional_claims={'role': u.role})
    print('Token:', token)

except Exception as e:
    traceback.print_exc()
