# QueueMed — Full Stack Setup

## Project Structure
```
projetpfa/
├── backend/          ← Flask + PostgreSQL
└── frontend/         ← Flutter
```

---

## Backend Setup

### 1. Create PostgreSQL database
```sql
CREATE DATABASE queueflowpfa;
```

### 2. Configure environment
Create `backend/.env` file:
```env
SECRET_KEY=your-secret-key
JWT_SECRET_KEY=your-jwt-secret-key
UPLOAD_FOLDER=uploads/

DB_HOST=localhost
DB_PORT=5432
DB_NAME=queueflowpfa
DB_USER=postgres
DB_PASSWORD=your_password
```

### 3. Install dependencies & migrate
```bash
cd backend
pip install -r requirements.txt

# Windows CMD
set FLASK_APP=run.py

# Git Bash / Linux / macOS
export FLASK_APP=run.py

flask db init
flask db migrate -m "initial"
flask db upgrade
```

### 4. Seed database (optional)
```bash
python seed.py          # Seed services
python seed_doctor.py   # Seed sample doctor
```

### 5. Run server
```bash
python run.py
# Server starts at http://0.0.0.0:5000
```

---

## Frontend Setup

### 1. Update IP in constants.dart
Edit `frontend/lib/constants.dart`:
```dart
const String kBaseUrl   = 'http://YOUR_IP:5000/api';
const String kSocketUrl = 'http://YOUR_IP:5000';
```

**Find your IP:**
- Windows: `ipconfig` (look for IPv4)
- Linux/macOS: `ifconfig` or `ip addr`

### 2. Install & run
```bash
cd frontend
flutter pub get
flutter run
```

---

## Database Tables

| Table               | Purpose                              |
|---------------------|--------------------------------------|
| users               | All users (patient/client/doctor/assistant) |
| patient_profiles    | Medical info for patients            |
| doctor_profiles     | Doctor specialty, availability       |
| assistant_profiles  | Assistant → service assignment       |
| services            | Bank, Post, Telecom, CNSS, Hospital  |
| queues              | Daily queue per service              |
| tickets             | Queue tickets with confirmation (3x) |
| appointments        | Doctor appointments with confirmation|
| medical_records     | Patient files (images, analyses)     |
| prescriptions       | Doctor prescriptions                 |
| notifications       | Real-time alerts                     |
| otp_codes           | OTP for verify/reset                 |

---

## Real-time Notification Logic

- When assistant calls next ticket → user with ticket 4 ahead gets **confirmation_request** notification
- User must confirm **3 times** to fully confirm arrival
- If user doesn't confirm after 3 calls → marked as **no_show**
- Patient gets notified when doctor **accepts/rejects** appointment
- Doctor gets notified when patient **confirms arrival** (3/3)

---

## User Roles

| Role       | Can do                                              |
|------------|-----------------------------------------------------|
| patient    | Book appointments, upload medical records, get prescriptions |
| client     | Take queue tickets at bank/post/telecom/CNSS        |
| doctor     | Manage appointments, view patient records, write prescriptions |
| assistant  | Manage queue, call next, scan QR, view dashboard    |

---

## Troubleshooting

### Backend won't start
- Check PostgreSQL is running
- Verify `.env` database credentials
- Run `flask db upgrade` to apply migrations

### Frontend can't connect
- Update IP in `constants.dart` (not localhost/127.0.0.1)
- Check backend is running on port 5000
- Disable firewall or allow port 5000

### Database errors
- Drop and recreate: `DROP DATABASE queueflowpfa; CREATE DATABASE queueflowpfa;`
- Re-run migrations: `flask db upgrade`