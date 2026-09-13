import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/api_client.dart';
import 'home_screen.dart';

enum _LoginStep { email, otp }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final otp = TextEditingController();
  final otpFocus = FocusNode();

  _LoginStep step = _LoginStep.email;
  bool busy = false;
  String? error;
  int resend = 0;
  int expires = 10;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    if (mounted) {
      email.text = preferences.getString('user_email') ?? '';
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    email.dispose();
    otp.dispose();
    otpFocus.dispose();
    super.dispose();
  }

  Future<String> device() async {
    final preferences = await SharedPreferences.getInstance();
    var id = preferences.getString('device_uuid');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await preferences.setString('device_uuid', id);
    }
    return id;
  }

  bool get validEmail => RegExp(
        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
      ).hasMatch(email.text.trim());

  Future<void> request({bool again = false}) async {
    FocusScope.of(context).unfocus();
    if (!validEmail) {
      setState(() => error = 'Enter a valid work email address.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final data = await ApiClient().requestOtp(email.text, await device());
      if (!mounted) return;
      setState(() {
        step = _LoginStep.otp;
        resend = int.tryParse(data['retry_after_seconds']?.toString() ?? '') ?? 60;
        expires = int.tryParse(data['expires_in_minutes']?.toString() ?? '') ?? 10;
        otp.clear();
      });
      _timer();
      otpFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            again
                ? 'A new verification code has been sent.'
                : 'A verification code has been sent to your email.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _timer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (value) {
      if (!mounted) {
        value.cancel();
        return;
      }
      if (resend <= 1) {
        value.cancel();
        setState(() => resend = 0);
      } else {
        setState(() => resend--);
      }
    });
  }

  Future<void> verify() async {
    FocusScope.of(context).unfocus();
    if (!RegExp(r'^\d{6}$').hasMatch(otp.text.trim())) {
      setState(() => error = 'Enter the 6-digit verification code.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      await ApiClient().verifyOtp(
        email.text,
        otp.text,
        await device(),
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _clean(Object value) =>
      value.toString().replaceFirst('Exception: ', '').trim();

  void changeEmail() {
    timer?.cancel();
    setState(() {
      step = _LoginStep.email;
      otp.clear();
      error = null;
      resend = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final verifyStep = step == _LoginStep.otp;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 64,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Five Star Attendance',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        verifyStep
                            ? 'Verify your email to continue'
                            : 'Sign in or register with your work email',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 26),
                      if (!verifyStep) ...[
                        TextField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !busy,
                          onSubmitted: (_) {
                            if (!busy) request();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Work email',
                            prefixIcon: Icon(Icons.alternate_email),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: busy ? null : request,
                          icon: const Icon(Icons.mail_outline),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              busy
                                  ? 'Sending code...'
                                  : 'Send verification code',
                            ),
                          ),
                        ),
                      ] else ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Code sent to'),
                          subtitle: Text(email.text.trim().toLowerCase()),
                          trailing: TextButton(
                            onPressed: busy ? null : changeEmail,
                            child: const Text('Change'),
                          ),
                        ),
                        TextField(
                          controller: otp,
                          focusNode: otpFocus,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 8,
                          ),
                          onSubmitted: (_) {
                            if (!busy) verify();
                          },
                          decoration: const InputDecoration(
                            labelText: '6-digit code',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Code expires in $expires minutes.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: busy ? null : verify,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              busy ? 'Verifying...' : 'Verify & sign in',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: busy || resend > 0
                              ? null
                              : () => request(again: true),
                          child: Text(
                            resend > 0
                                ? 'Resend code in ${resend}s'
                                : 'Resend verification code',
                          ),
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(error!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
