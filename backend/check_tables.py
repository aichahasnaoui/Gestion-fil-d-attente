import traceback
try:
    from app import create_app
    from app.extensions import db
    from sqlalchemy import inspect
    app = create_app()
    with app.app_context():
        db.create_all()
        inspector = inspect(db.engine)
        tables = inspector.get_table_names()
        print('Tables:', tables)
except Exception:
    traceback.print_exc()
