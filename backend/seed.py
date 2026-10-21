"""
Run once to seed sample services:
    cd backend
    python seed.py
"""
# import eventlet
# eventlet.monkey_patch()

from app import create_app
from app.extensions import db
from app.models import Service

SERVICES = [
    {'name': 'BNA Tunis Centre',      'type': 'bank',    'address': 'Av. Habib Bourguiba', 'wilaya': 'Tunis'},
    {'name': 'La Poste Bab Bhar',     'type': 'post',    'address': 'Rue de la Kasbah',    'wilaya': 'Tunis'},
    {'name': 'Ooredoo Agence Lac',    'type': 'telecom', 'address': 'Les Berges du Lac',   'wilaya': 'Tunis'},
    {'name': 'CNSS Ariana',           'type': 'cnss',    'address': 'Av. Ataturk',         'wilaya': 'Ariana'},
    {'name': 'Hopital Charles Nicolle','type': 'hospital','address': 'Bd du 9 Avril',      'wilaya': 'Tunis'},
    {'name': 'Clinique El Manar',     'type': 'clinic',  'address': 'Rue Ibn Khaldoun',    'wilaya': 'Tunis'},
    {'name': 'STB Sfax',              'type': 'bank',    'address': 'Av. Hedi Chaker',     'wilaya': 'Sfax'},
    {'name': 'La Poste Sousse',       'type': 'post',    'address': 'Av. Bourguiba',       'wilaya': 'Sousse'},
]

app = create_app()
with app.app_context():
    for s in SERVICES:
        if not Service.query.filter_by(name=s['name']).first():
            db.session.add(Service(**s))
    db.session.commit()
    print("[OK] Services seeded:", Service.query.count(), "total")
