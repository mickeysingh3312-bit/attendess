import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/api_client.dart';
import 'home_screen.dart';

enum _LoginStep { email, password, createPassword }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final passwordConfirmation = TextEditingController();
  final passwordFocus = FocusNode();

  _LoginStep step = _LoginStep.email;
  String accountMode = '';
  bool busy = false;
  bool showPassword = false;
  bool showPasswordConfirmation = false;
  String? error;

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
    email.dispose();
    password.dispose();
    passwordConfirmation.dispose();
    passwordFocus.dispose();
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
        password.clear();
        passwordConfirmation.clear();
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

  Future<void> createPassword() async {
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
      await ApiClient().setPassword(
        email: email.text,
        password: password.text,
        passwordConfirmation: passwordConfirmation.text,
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

  void changeEmail() {
    setState(() {
      step = _LoginStep.email;
      accountMode = '';
      password.clear();
      passwordConfirmation.clear();
      error = null;
    });
  }

  void passwordHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password'),
        content: const Text(
          'Contact your attendance administrator. They can enable password setup for your account, then you can create a new password in the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _clean(Object value) => ApiClient.friendlyError(value).trim();

  String get heading {
    switch (step) {
      case _LoginStep.password:
        return 'Welcome back';
      case _LoginStep.createPassword:
        if (accountMode == 'register') return 'Create your account';
        return 'Create your password';
      case _LoginStep.email:
        return 'Sign in to continue';
    }
  }

  String get subtitle {
    switch (step) {
      case _LoginStep.password:
        return 'Enter your password to open attendance.';
      case _LoginStep.createPassword:
        if (accountMode == 'register') {
          return 'Create your login, then complete your Site Access Staff profile.';
        }
        return 'This is a one-time setup for your existing staff account.';
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
                          onPressed: busy ? null : passwordHelp,
                          child: const Text('Forgot password?'),
                        ),
                      ],
                      if (step == _LoginStep.createPassword) ...[
                        accountTile(),
                        const SizedBox(height: 8),
                        passwordField(
                          controller: password,
                          label: 'Create password',
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
                            if (!busy) createPassword();
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Use at least 8 characters with a letter and a number.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: busy ? null : createPassword,
                          icon: const Icon(Icons.lock_open_outlined),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              busy
                                  ? 'Saving password...'
                                  : 'Save password & continue',
                            ),
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
