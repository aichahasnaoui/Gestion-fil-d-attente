from app import create_app
from app.models import User
from app.extensions import db
app = create_app()
with app.app_context():
    User.query.update({'is_verified': True, 'is_active': True})
    db.session.commit()
    print("All users verified and activated")
