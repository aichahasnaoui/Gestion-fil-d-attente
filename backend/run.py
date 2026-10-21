# from gevent import monkey
# monkey.patch_all()

import sys

try:
    from app import create_app
    from app.extensions import socketio
except Exception as e:
    print("ERROR importing app:", e)
    import traceback; traceback.print_exc()
    sys.exit(1)

try:
    app = create_app()
    print("App created OK")
except Exception as e:
    print("ERROR creating app:", e)
    import traceback; traceback.print_exc()
    sys.exit(1)

if __name__ == '__main__':
    print("Starting server on http://0.0.0.0:5000 ...")
    socketio.run(
        app,
        host='0.0.0.0',
        port=5000,
        debug=True,
        use_reloader=False,
        allow_unsafe_werkzeug=True,
    )
 
