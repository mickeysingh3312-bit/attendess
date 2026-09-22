# Mobile Password Login Build

Version: `0.6.0+12`

Deploy the Laravel password-login backend and run its migration before distributing this mobile build.

The mobile login flow is now:

1. Enter work email.
2. Existing configured users enter their password.
3. First-time or new users create and confirm a password.
4. First-time setup, registration, and password reset require one email verification code.
5. Normal future sign-ins use email and password only.

To build locally:

```bash
cd mobile
flutter pub get
flutter analyze --no-fatal-infos
flutter build apk --release
```

Pushing the updated `mobile/` source to the repository's `main` branch also triggers the Android APK workflow. The generated artifact is named `five-star-attendance-v0.6.0-password-login`.
