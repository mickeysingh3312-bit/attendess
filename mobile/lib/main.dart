import 'dart:ui';

import 'package:flutter/material.dart';

import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep framework/async Dart errors inside Flutter instead of allowing an
  // unexpected screen initialization problem to terminate the user flow.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled app error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };
  ErrorWidget.builder = (details) => Material(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 52),
                  const SizedBox(height: 16),
                  const Text(
                    'The app could not load this screen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details.exceptionAsString(),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff17365d);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Five Star Attendance',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff7f8fb),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      // Safe-start: always enter through the OTP screen. This prevents restored
      // stale session data from eagerly booting Home/Profile on process start.
      home: const LoginScreen(),
    );
  }
}
