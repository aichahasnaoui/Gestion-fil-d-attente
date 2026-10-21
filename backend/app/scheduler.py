from datetime import datetime, timedelta
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger

_scheduler = None
TZ_OFFSET = timedelta(hours=1)


def _local_time_str(dt_utc):
    return (dt_utc + TZ_OFFSET).strftime('%H:%M')


def _auto_call_next(app):
    """Server-side: auto-call next ticket every 5 min + cancel no-shows."""
    from .extensions import db, socketio
    from .models import Queue, Ticket, Service, Notification
    from datetime import date

    with app.app_context():
        today = date.today()
        queues = Queue.query.filter_by(date=today, is_open=True).all()

        for queue in queues:
            # 1. Cancel called tickets not confirmed after 5 min
            cutoff = datetime.utcnow() - timedelta(minutes=5)
            stale = Ticket.query.filter(
                Ticket.queue_id == queue.id,
                Ticket.status == 'called',
                Ticket.called_at < cutoff,
                Ticket.confirmation_count == 0,
            ).all()
            for t in stale:
                t.status = 'no_show'
                t.cancelled_at = datetime.utcnow()
                n = Notification(
                    user_id=t.user_id, type='ticket_alert',
                    title='Ticket annule automatiquement',
                    body=f'Votre ticket #{t.ticket_number} a ete annule car vous ne vous etes pas presente a temps.',
                    data={'ticket_id': t.id, 'service_id': queue.service_id},
                )
                db.session.add(n)
                db.session.flush()
                socketio.emit('notification', n.to_dict(), room=f'user_{t.user_id}')

            # 2. Skip if a ticket is already being called
            active = Ticket.query.filter_by(queue_id=queue.id, status='called').count()
            if active > 0:
                continue

            # 3. Call next active ticket, including users who already confirmed 3/3.
            ticket = Ticket.query.filter(Ticket.queue_id == queue.id)\
                .filter(Ticket.status.in_(['waiting', 'confirmed']))\
                .order_by(Ticket.ticket_number).first()

            if not ticket:
                continue

            ticket.status = 'called'
            ticket.called_at = datetime.utcnow()
            queue.current_number = ticket.ticket_number

            service = Service.query.get(queue.service_id)
            sname = service.name if service else 'le service'

            # Notify the called user
            n_call = Notification(
                user_id=ticket.user_id, type='ticket_alert',
                title=f"C'est votre tour ! Ticket {ticket.ticket_number}",
                body=f'Veuillez vous presenter au guichet chez {sname}. Confirmez votre presence !',
                data={'ticket_id': ticket.id, 'service_id': queue.service_id, 'action': 'confirm_arrival'},
            )
            db.session.add(n_call)
            db.session.flush()
            socketio.emit('notification', n_call.to_dict(), room=f'user_{ticket.user_id}')

            # Send confirmation_request to users 1, 2, 3 ahead
            from .routes.tickets import _ahead_count
            waiting_tickets = Ticket.query.filter_by(
                queue_id=queue.id, status='waiting'
            ).order_by(Ticket.ticket_number).all()

            for t in waiting_tickets:
                ahead = _ahead_count(queue.id, t.ticket_number)
                if ahead in [1, 2, 3]:
                    n_alert = Notification(
                        user_id=t.user_id, type='confirmation_request',
                        title=f'Plus que {ahead} personne(s) avant vous !',
                        body=f'Il reste {ahead} personne(s) avant votre tour chez {sname}. '
                             f'Confirmez votre presence ou votre ticket sera annule.',
                        data={'ticket_id': t.id, 'service_id': queue.service_id, 'ahead': ahead},
                    )
                    db.session.add(n_alert)
                    db.session.flush()
                    socketio.emit('notification', n_alert.to_dict(), room=f'user_{t.user_id}')

            socketio.emit('queue_update', {
                'service_id': queue.service_id,
                'current_number': queue.current_number,
            }, room=f'service_{queue.service_id}')

        db.session.commit()


def _send_reminders(app):
    from .extensions import db, socketio
    from .models import Appointment, Notification

    with app.app_context():
        now = datetime.utcnow()

        for minutes_before, label in [(30, '30 minutes'), (5, '5 minutes')]:
            window_start = now + timedelta(minutes=minutes_before - 1)
            window_end   = now + timedelta(minutes=minutes_before + 1)

            appts = Appointment.query.filter(
                Appointment.scheduled_at >= window_start,
                Appointment.scheduled_at <= window_end,
                Appointment.status.in_(['accepted', 'confirmed', 'pending']),
            ).all()

            for appt in appts:
                already = Notification.query.filter_by(
                    user_id=appt.patient_id,
                    type='appointment_reminder',
                ).filter(
                    Notification.data.op('->>')('appointment_id').cast(db.Integer) == appt.id,
                    Notification.data.op('->>')('minutes_before') == str(minutes_before),
                ).first()

                if already:
                    continue

                doctor_name = 'votre medecin'
                try:
                    doctor_name = f'Dr. {appt.doctor.user.full_name}'
                except Exception:
                    pass

                appt_time = _local_time_str(appt.scheduled_at)
                title = f'Rappel - Rendez-vous dans {label}'
                body  = (
                    f'Votre rendez-vous avec {doctor_name} '
                    f'est prevu a {appt_time}. '
                    f'Il commence dans {label}, preparez-vous !'
                )

                n = Notification(
                    user_id=appt.patient_id,
                    type='appointment_reminder',
                    title=title, body=body,
                    data={
                        'appointment_id': appt.id,
                        'minutes_before': str(minutes_before),
                        'appointment_time': appt_time,
                    },
                )
                db.session.add(n)
                db.session.flush()
                socketio.emit('notification', n.to_dict(), room=f'user_{appt.patient_id}')

        db.session.commit()


def start_scheduler(app):
    global _scheduler
    if _scheduler is not None:
        return
    _scheduler = BackgroundScheduler(timezone='UTC')

    # Appointment reminders — every minute
    _scheduler.add_job(
        func=lambda: _send_reminders(app),
        trigger=IntervalTrigger(minutes=1),
        id='appointment_reminders',
        replace_existing=True,
    )

    # Auto-call next ticket + cancel no-shows — every 5 minutes
    _scheduler.add_job(
        func=lambda: _auto_call_next(app),
        trigger=IntervalTrigger(minutes=5),
        id='auto_call_next',
        replace_existing=True,
    )

    _scheduler.start()
