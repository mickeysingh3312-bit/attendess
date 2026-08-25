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

Secrets such as Airtable tokens, database credentials, and mobile signing keys must stay in environment/CI settings and are not committed to this repository.
