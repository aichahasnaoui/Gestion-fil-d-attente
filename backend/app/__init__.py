import os
from flask import Flask, jsonify
from werkzeug.exceptions import HTTPException
from .extensions import db, migrate, jwt, bcrypt, socketio, cors
from dotenv import load_dotenv

load_dotenv()

def create_app():
    app = Flask(__name__)

    app.config['SECRET_KEY']                  = os.getenv('SECRET_KEY', 'dev-secret')
    app.config['JWT_SECRET_KEY']              = os.getenv('JWT_SECRET_KEY', 'dev-jwt-secret')
    app.config['SQLALCHEMY_DATABASE_URI']     = (
        f"postgresql://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}"
        f"@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
    )
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    app.config['UPLOAD_FOLDER']               = os.getenv('UPLOAD_FOLDER', 'uploads/')
    app.config['MAX_CONTENT_LENGTH']          = 20 * 1024 * 1024  # 20 MB

    # Init extensions
    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    bcrypt.init_app(app)
    cors.init_app(app, resources={r"/*": {"origins": "*"}})
    socketio.init_app(app)

    # Register blueprints
    from .routes.auth          import auth_bp
    from .routes.users         import users_bp
    from .routes.services      import services_bp
    from .routes.tickets       import tickets_bp
    from .routes.appointments  import appointments_bp
    from .routes.doctors       import doctors_bp
    from .routes.records       import records_bp
    from .routes.notifications import notifications_bp
    from .routes.service_admin import service_admin_bp
    from .routes.messages      import messages_bp

    for bp in [auth_bp, users_bp, services_bp, tickets_bp,
               appointments_bp, doctors_bp, records_bp,
               notifications_bp, service_admin_bp]:
        app.register_blueprint(bp, url_prefix='/api')

    # Chat: enregistré sous /api/chat pour correspondre aux appels Flutter
    app.register_blueprint(messages_bp, url_prefix='/api/chat')

    # Register socket events
    from .sockets import events  # noqa

    # Start reminder scheduler
    from .scheduler import start_scheduler
    start_scheduler(app)

    # Ensure upload folder exists
    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

    # Error handlers
    @app.errorhandler(400)
    def bad_request(e):
        return {'error': str(e)}, 400

    @app.errorhandler(401)
    def unauthorized(e):
        return {'error': 'Unauthorized'}, 401

    @app.errorhandler(404)
    def not_found(e):
        return {'error': 'Not found'}, 404

    @app.errorhandler(500)
    def internal_error(e):
        return {'error': 'Internal server error'}, 500

    @app.errorhandler(Exception)
    def handle_exception(e):
        if isinstance(e, HTTPException):
            return {'error': e.description}, e.code
        return {'error': str(e)}, 500

    return app
