@echo off
echo === QueueMed Backend Setup ===

cd /d %~dp0

echo Installing dependencies...
pip install -r requirements.txt

echo Initializing database migrations...
set FLASK_APP=run.py
flask db init
flask db migrate -m "initial schema"
flask db upgrade

echo Done! Run: python run.py
