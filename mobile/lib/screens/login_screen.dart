import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/api_client.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget { const LoginScreen({super.key}); @override State<LoginScreen> createState() => _LoginScreenState(); }
class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  @override void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) { setState(() => error = 'Enter your email and password.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final p = await SharedPreferences.getInstance();
      var id = p.getString('device_uuid');
      if (id == null) { id = const Uuid().v4(); await p.setString('device_uuid', id); }
      await ApiClient().login(email.text.trim(), password.text, id);
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Icon(Icons.location_on, size: 72), const SizedBox(height: 14), Text('Five Star Attendance', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center), const SizedBox(height: 28), TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: password, obscureText: true, onSubmitted: (_) { if (!busy) submit(); }, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())), if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))), const SizedBox(height: 18), FilledButton(onPressed: busy ? null : submit, child: Padding(padding: const EdgeInsets.all(14), child: Text(busy ? 'Signing in...' : 'Sign in')))]))))));
}
