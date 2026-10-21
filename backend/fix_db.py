import traceback
try:
    from app import create_app
    from app.extensions import db
    from sqlalchemy import inspect, text

    app = create_app()
    ctx = app.app_context()
    ctx.push()

    # Create all tables that don't exist yet
    db.create_all()
    print('[OK] db.create_all() done')

    # Fix broken alembic version
    inspector = inspect(db.engine)
    tables = inspector.get_table_names()
    print('Tables in DB:', tables)

    # Stamp alembic to current head so future migrations work
    if 'alembic_version' in tables:
        with db.engine.connect() as conn:
            conn.execute(text("DELETE FROM alembic_version"))
            conn.commit()
        print('[OK] Cleared broken alembic_version')

    if 'messages' in tables:
        columns = {c['name'] for c in inspector.get_columns('messages')}
        statements = []
        if 'attachment_url' not in columns:
            statements.append("ALTER TABLE messages ADD COLUMN attachment_url VARCHAR(300)")
        if 'attachment_type' not in columns:
            statements.append("ALTER TABLE messages ADD COLUMN attachment_type VARCHAR(50)")
        if 'attachment_name' not in columns:
            statements.append("ALTER TABLE messages ADD COLUMN attachment_name VARCHAR(200)")

        if statements:
            with db.engine.connect() as conn:
                for stmt in statements:
                    conn.execute(text(stmt))
                conn.commit()
            print('[OK] Added message attachment columns')

except Exception as e:
    traceback.print_exc()
