import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(AttendanceApp(loggedIn: preferences.getString('token') != null));
}

class AttendanceApp extends StatelessWidget {
  final bool loggedIn;
  const AttendanceApp({super.key, required this.loggedIn});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Five Star Attendance',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff172033)), useMaterial3: true),
    home: loggedIn ? const HomeScreen() : const LoginScreen(),
  );
}
