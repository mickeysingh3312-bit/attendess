# Mobile Password Login Build

Version: `0.6.3+15`

Deploy the Laravel password-login backend and run its migration before distributing this mobile build.

The mobile login flow is now:

1. Enter work email.
2. Existing configured users enter their password.
3. First-time or new users create and confirm a password.
4. The password is saved immediately without an email verification code.
5. Normal future sign-ins use email and password only.
6. Forgotten passwords are reset by an administrator, who enables password setup again for the employee.

To build locally:

```bash
cd mobile
flutter pub get
flutter analyze --no-fatal-infos
flutter build apk --release
```

Pushing the updated `mobile/` source to the repository's `main` branch also triggers the Android APK workflow. The generated artifact is named `five-star-attendance-v0.6.3-location-recovery`.
