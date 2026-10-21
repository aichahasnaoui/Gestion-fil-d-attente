import traceback
try:
    from app import create_app
    from app.models import Ticket, Queue, Service
    from datetime import date
    app = create_app()
    ctx = app.app_context()
    ctx.push()
    today = date.today()
    queues = Queue.query.filter_by(date=today).all()
    print('Queues today:', len(queues))
    for q in queues:
        s = Service.query.get(q.service_id)
        tickets = Ticket.query.filter_by(queue_id=q.id).all()
        print(f'  Service: {s.name if s else q.service_id} | is_open={q.is_open} | current={q.current_number} | total={q.total_issued}')
        for t in tickets:
            print(f'    ticket#{t.ticket_number} status={t.status} user={t.user_id} called_at={t.called_at} confirm={t.confirmation_count}')
    if not queues:
        print('No queues today - checking all tickets:')
        tickets = Ticket.query.order_by(Ticket.issued_at.desc()).limit(10).all()
        for t in tickets:
            print(f'  ticket#{t.ticket_number} status={t.status} queue={t.queue_id} issued={t.issued_at}')
except Exception as e:
    traceback.print_exc()
