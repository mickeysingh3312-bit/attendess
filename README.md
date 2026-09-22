# Five Star Site Attendance

Automatic site attendance system using Airtable project locations, mobile geofencing, and a Laravel web/API backend.

## Components

- `backend/` - Laravel 12 API and web admin portal (PHP 8.2)
- `mobile/` - Flutter mobile app foundation with Android native geofencing integration
- `docs/` - architecture, API, and setup documentation

## Core flow

1. Projects are synchronized from Airtable into the attendance database.
2. Staff are assigned to relevant projects/geofences.
3. The mobile app registers those geofences with the phone OS.
4. ENTER events create an automatic check-in.
5. EXIT events are verified/delayed before final automatic checkout to reduce false GPS transitions.
6. Attendance appears in the web portal and can later be exported for reporting/payroll.

## Mobile authentication

- Staff enter their email first.
- Existing users sign in with email and password.
- First-time Airtable users create a password and verify their email once.
- New users create a password, verify their email, and then complete the Site Access Staff profile.
- Verification codes are used only for password setup and recovery, not routine login.

Secrets such as Airtable tokens, database credentials, and mobile signing keys must stay in environment/CI settings and are not committed to this repository.
