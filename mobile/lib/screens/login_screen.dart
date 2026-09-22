import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/api_client.dart';
import 'home_screen.dart';

enum _LoginStep { email, password, createPassword, verify }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final passwordConfirmation = TextEditingController();
  final verificationCode = TextEditingController();
  final passwordFocus = FocusNode();
  final verificationFocus = FocusNode();

  _LoginStep step = _LoginStep.email;
  String accountMode = '';
  bool resetMode = false;
  bool busy = false;
  bool showPassword = false;
  bool showPasswordConfirmation = false;
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
    if (mounted) email.text = preferences.getString('user_email') ?? '';
  }

  @override
  void dispose() {
    timer?.cancel();
    email.dispose();
    password.dispose();
    passwordConfirmation.dispose();
    verificationCode.dispose();
    passwordFocus.dispose();
    verificationFocus.dispose();
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

  bool get validNewPassword {
    final value = password.text;
    return value.length >= 8 &&
        RegExp(r'[A-Za-z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value);
  }

  Future<void> checkEmail() async {
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
      final data = await ApiClient().accountStatus(email.text);
      if (!mounted) return;
      final mode = data['mode']?.toString() ?? '';

      if (mode == 'unavailable') {
        setState(() => error = data['message']?.toString() ??
            'This account is not available. Please contact your administrator.');
        return;
      }

      setState(() {
        accountMode = mode;
        resetMode = false;
        password.clear();
        passwordConfirmation.clear();
        verificationCode.clear();
        step = mode == 'login'
            ? _LoginStep.password
            : _LoginStep.createPassword;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) passwordFocus.requestFocus();
      });
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> login() async {
    FocusScope.of(context).unfocus();
    if (password.text.isEmpty) {
      setState(() => error = 'Enter your password.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      await ApiClient().loginWithPassword(
        email.text,
        password.text,
        await device(),
      );
      _openHome();
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> requestPasswordCode({bool again = false}) async {
    FocusScope.of(context).unfocus();
    if (!validNewPassword) {
      setState(() => error =
          'Use at least 8 characters with at least one letter and one number.');
      return;
    }
    if (password.text != passwordConfirmation.text) {
      setState(() => error = 'The password confirmation does not match.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final data = await ApiClient().requestPasswordCode(
        email: email.text,
        password: password.text,
        passwordConfirmation: passwordConfirmation.text,
        deviceUuid: await device(),
        reset: resetMode,
      );
      if (!mounted) return;
      setState(() {
        step = _LoginStep.verify;
        resend = int.tryParse(
              data['retry_after_seconds']?.toString() ?? '',
            ) ??
            60;
        expires = int.tryParse(
              data['expires_in_minutes']?.toString() ?? '',
            ) ??
            10;
        verificationCode.clear();
      });
      _startTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) verificationFocus.requestFocus();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            again
                ? 'A new verification code has been sent.'
                : 'Check your email for the verification code.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmPasswordCode() async {
    FocusScope.of(context).unfocus();
    if (!RegExp(r'^\d{6}$').hasMatch(verificationCode.text.trim())) {
      setState(() => error = 'Enter the 6-digit verification code.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      await ApiClient().confirmPasswordCode(
        email: email.text,
        verificationCode: verificationCode.text,
        deviceUuid: await device(),
      );
      _openHome();
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _openHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _startTimer() {
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

  void startReset() {
    setState(() {
      step = _LoginStep.createPassword;
      resetMode = true;
      password.clear();
      passwordConfirmation.clear();
      error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) passwordFocus.requestFocus();
    });
  }

  void changeEmail() {
    timer?.cancel();
    setState(() {
      step = _LoginStep.email;
      accountMode = '';
      resetMode = false;
      password.clear();
      passwordConfirmation.clear();
      verificationCode.clear();
      resend = 0;
      error = null;
    });
  }

  void backFromReset() {
    setState(() {
      step = _LoginStep.password;
      resetMode = false;
      password.clear();
      passwordConfirmation.clear();
      error = null;
    });
  }

  String _clean(Object value) => ApiClient.friendlyError(value).trim();

  String get heading {
    switch (step) {
      case _LoginStep.password:
        return 'Welcome back';
      case _LoginStep.createPassword:
        if (resetMode) return 'Reset your password';
        if (accountMode == 'register') return 'Create your account';
        return 'Create your password';
      case _LoginStep.verify:
        return 'Verify your email';
      case _LoginStep.email:
        return 'Sign in to continue';
    }
  }

  String get subtitle {
    switch (step) {
      case _LoginStep.password:
        return 'Enter your password to open attendance.';
      case _LoginStep.createPassword:
        if (resetMode) return 'Choose a new password for your account.';
        if (accountMode == 'register') {
          return 'Create your login, then complete your Site Access Staff profile.';
        }
        return 'This is a one-time setup for your existing staff account.';
      case _LoginStep.verify:
        return 'Enter the code sent to ${email.text.trim().toLowerCase()}.';
      case _LoginStep.email:
        return 'Use your work email to sign in or register.';
    }
  }

  Widget passwordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback toggle,
    FocusNode? focusNode,
    TextInputAction action = TextInputAction.next,
    VoidCallback? submitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: !busy,
      obscureText: !visible,
      autofillHints: const [AutofillHints.password],
      textInputAction: action,
      onSubmitted: (_) => submitted?.call(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: toggle,
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget accountTile() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(email.text.trim().toLowerCase()),
      subtitle: const Text('Work email'),
      trailing: TextButton(
        onPressed: busy ? null : changeEmail,
        child: const Text('Change'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
                      const SizedBox(height: 8),
                      Text(
                        heading,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(subtitle, textAlign: TextAlign.center),
                      const SizedBox(height: 26),
                      if (step == _LoginStep.email) ...[
                        TextField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.done,
                          enabled: !busy,
                          onSubmitted: (_) {
                            if (!busy) checkEmail();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Work email',
                            prefixIcon: Icon(Icons.alternate_email),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: busy ? null : checkEmail,
                          icon: const Icon(Icons.arrow_forward),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              busy ? 'Checking account...' : 'Continue',
                            ),
                          ),
                        ),
                      ],
                      if (step == _LoginStep.password) ...[
                        accountTile(),
                        const SizedBox(height: 8),
                        passwordField(
                          controller: password,
                          label: 'Password',
                          visible: showPassword,
                          toggle: () =>
                              setState(() => showPassword = !showPassword),
                          focusNode: passwordFocus,
                          action: TextInputAction.done,
                          submitted: () {
                            if (!busy) login();
                          },
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: busy ? null : login,
                          icon: const Icon(Icons.login),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(busy ? 'Signing in...' : 'Sign in'),
                          ),
                        ),
                        TextButton(
                          onPressed: busy ? null : startReset,
                          child: const Text('Forgot password?'),
                        ),
                      ],
                      if (step == _LoginStep.createPassword) ...[
                        accountTile(),
                        const SizedBox(height: 8),
                        passwordField(
                          controller: password,
                          label: resetMode ? 'New password' : 'Create password',
                          visible: showPassword,
                          toggle: () =>
                              setState(() => showPassword = !showPassword),
                          focusNode: passwordFocus,
                        ),
                        const SizedBox(height: 12),
                        passwordField(
                          controller: passwordConfirmation,
                          label: 'Confirm password',
                          visible: showPasswordConfirmation,
                          toggle: () => setState(() =>
                              showPasswordConfirmation =
                                  !showPasswordConfirmation),
                          action: TextInputAction.done,
                          submitted: () {
                            if (!busy) requestPasswordCode();
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Use at least 8 characters with a letter and a number.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: busy ? null : requestPasswordCode,
                          icon: const Icon(Icons.mark_email_read_outlined),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              busy
                                  ? 'Sending verification...'
                                  : 'Verify email & continue',
                            ),
                          ),
                        ),
                        if (resetMode)
                          TextButton(
                            onPressed: busy ? null : backFromReset,
                            child: const Text('Back to sign in'),
                          ),
                      ],
                      if (step == _LoginStep.verify) ...[
                        accountTile(),
                        const SizedBox(height: 8),
                        TextField(
                          controller: verificationCode,
                          focusNode: verificationFocus,
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
                            if (!busy) confirmPasswordCode();
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
                          onPressed: busy ? null : confirmPasswordCode,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              busy ? 'Verifying...' : 'Confirm & continue',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: busy || resend > 0
                              ? null
                              : () => requestPasswordCode(again: true),
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
