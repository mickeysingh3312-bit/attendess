# Android build and geofencing

The mobile app uses Flutter for UI/API access and native Android geofencing for background ENTER/EXIT events.

GitHub Actions creates a fresh Android scaffold, installs the native Kotlin files, analyzes the Flutter source, builds a debug APK, and uploads it as `five-star-attendance-debug-apk` with 1-day retention.

Set repository variable `ATTENDANCE_API_BASE_URL` to the production HTTPS endpoint ending in `/api/mobile`. Without it the APK builds with a placeholder URL and cannot log in to the real backend.

Required user settings: Precise location, Allow location all the time, notifications, and Location services enabled. Geofences are restored after device reboot/app update. Android Force Stop disables background execution until the user opens the app again.
