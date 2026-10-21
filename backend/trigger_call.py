import traceback
try:
    from app import create_app
    from app.scheduler import _auto_call_next
    app = create_app()
    print('Triggering auto-call now...')
    _auto_call_next(app)
    print('Done - check notifications')
except Exception as e:
    traceback.print_exc()
