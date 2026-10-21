import traceback
try:
    from app import create_app
    from app.models import Service
    app = create_app()
    ctx = app.app_context()
    ctx.push()
    services = Service.query.all()
    print('Total services:', len(services))
    for s in services:
        print(f'  id={s.id} name={s.name} type={s.type} is_active={s.is_active} wilaya={s.wilaya}')
except Exception as e:
    traceback.print_exc()
