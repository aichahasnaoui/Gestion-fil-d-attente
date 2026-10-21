import traceback
try:
    from app import create_app
    from app.extensions import db
    from app.models import Ticket, Queue
    from datetime import date
    app = create_app()
    ctx = app.app_context()
    ctx.push()
    today = date.today()
    queues = Queue.query.filter_by(date=today).all()
    for q in queues:
        # Reset confirmed tickets that were never called back to waiting
        tickets = Ticket.query.filter_by(queue_id=q.id, status='confirmed').filter(
            Ticket.called_at == None
        ).all()
        for t in tickets:
            t.status = 'waiting'
            t.confirmation_count = 0
            print(f'Reset ticket#{t.ticket_number} -> waiting (service={q.service_id})')
    db.session.commit()
    print('Done')
except Exception as e:
    traceback.print_exc()
