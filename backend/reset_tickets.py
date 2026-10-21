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
        tickets = Ticket.query.filter_by(queue_id=q.id).filter(
            Ticket.status.in_(['confirmed', 'waiting', 'called'])
        ).all()
        for t in tickets:
            t.status = 'cancelled'
            print(f'Cancelled ticket#{t.ticket_number} service={q.service_id}')
        q.current_number = 0
        q.total_issued = 0
    db.session.commit()
    print('Done - all active tickets cancelled, queues reset')
except Exception as e:
    traceback.print_exc()
