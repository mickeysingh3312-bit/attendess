import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../services/api_client.dart';
import 'home_screen.dart';

enum _LoginStep { email, otp }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _otpFocus = FocusNode();

  _LoginStep _step = _LoginStep.email;
  bool _busy = false;
  String? _error;
  int _resendSeconds = 0;
  int _expiresMinutes = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restoreLastEmail();
  }

  Future<void> _restoreLastEmail() async {
    final preferences = await SharedPreferences.getInstance();
    final savedEmail = preferences.getString('user_email');
    if (savedEmail != null && mounted) {
      _emailController.text = savedEmail;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  Future<String> _deviceUuid() async {
    final preferences = await SharedPreferences.getInstance();
    var id = preferences.getString('device_uuid');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await preferences.setString('device_uuid', id);
    }
    return id;
  }

  bool get _validEmail {
    final value = _emailController.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  Future<void> _requestOtp({bool resend = false}) async {
    FocusScope.of(context).unfocus();
    if (!_validEmail) {
      setState(() => _error = 'Enter a valid work email address.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final data = await ApiClient().requestOtp(
        _emailController.text,
        await _deviceUuid(),
      );
      final retry = int.tryParse(data['retry_after_seconds']?.toString() ?? '') ?? 60;
      final expires = int.tryParse(data['expires_in_minutes']?.toString() ?? '') ?? 10;

      if (!mounted) return;
      setState(() {
        _step = _LoginStep.otp;
        _resendSeconds = retry.clamp(0, 600);
        _expiresMinutes = expires.clamp(1, 60);
        _otpController.clear();
      });
      _startResendTimer();
      _otpFocus.requestFocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resend
                ? 'A new verification code has been requested.'
                : 'If this email is registered, a verification code has been sent.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = _cleanError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _verifyOtp() async {
    FocusScope.of(context).unfocus();
    final code = _otpController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit verification code.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ApiClient().verifyOtp(
        _emailController.text,
        code,
        await _deviceUuid(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = _cleanError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();

  void _changeEmail() {
    _timer?.cancel();
    setState(() {
      _step = _LoginStep.email;
      _otpController.clear();
      _error = null;
      _resendSeconds = 0;
    });
  }

  Future<void> _showConnectionSettings() async {
    final controller = TextEditingController(text: await AppConfig.apiBaseUrl());
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        var saving = false;
        String? localError;
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Connection settings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Normally you do not need to change this. Use the Attendance website address if your server URL changes.',
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Attendance API URL',
                    hintText: 'https://attendance.example.com/api/mobile',
                    border: const OutlineInputBorder(),
                    errorText: localError,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final normalized = AppConfig.normalizeApiBaseUrl(controller.text);
                          final uri = Uri.tryParse(normalized);
                          if (uri == null ||
                              !uri.hasScheme ||
                              uri.host.isEmpty ||
                              (uri.scheme != 'https' && uri.scheme != 'http')) {
                            setSheetState(() => localError = 'Enter a valid web address.');
                            return;
                          }
                          setSheetState(() {
                            saving = true;
                            localError = null;
                          });
                          await AppConfig.setApiBaseUrl(normalized);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                  child: const Text('Save connection'),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          await AppConfig.resetApiBaseUrl();
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                  child: const Text('Use build default'),
                ),
              ],
            ),
          ),
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isOtp = _step == _LoginStep.otp;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.primaryContainer.withValues(alpha: 0.72),
                      colors.surface,
                      colors.surface,
                    ],
                    stops: const [0, 0.42, 1],
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: colors.onPrimary,
                                size: 40,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Five Star Attendance',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isOtp
                                ? 'Verify your email to continue'
                                : 'Sign in with your work email',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 28),
                          if (!isOtp) ...[
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.email],
                              autocorrect: false,
                              enabled: !_busy,
                              onSubmitted: (_) {
                                if (!_busy) _requestOtp();
                              },
                              decoration: const InputDecoration(
                                labelText: 'Work email',
                                prefixIcon: Icon(Icons.alternate_email_rounded),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _busy ? null : () => _requestOtp(),
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.mail_outline_rounded),
                              label: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Text(_busy ? 'Sending code...' : 'Send verification code'),
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Code sent to'),
                                        const SizedBox(height: 2),
                                        Text(
                                          _emailController.text.trim().toLowerCase(),
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _busy ? null : _changeEmail,
                                    child: const Text('Change'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _otpController,
                              focusNode: _otpFocus,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 10,
                              ),
                              enabled: !_busy,
                              onSubmitted: (_) {
                                if (!_busy) _verifyOtp();
                              },
                              decoration: const InputDecoration(
                                labelText: '6-digit code',
                                hintText: '000000',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'The code expires in $_expiresMinutes minutes.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _busy ? null : _verifyOtp,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.verified_user_outlined),
                              label: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Text(_busy ? 'Verifying...' : 'Verify & sign in'),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: _busy || _resendSeconds > 0
                                  ? null
                                  : () => _requestOtp(resend: true),
                              child: Text(
                                _resendSeconds > 0
                                    ? 'Resend code in ${_resendSeconds}s'
                                    : 'Resend verification code',
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.error_outline, color: colors.onErrorContainer),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(color: colors.onErrorContainer),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          TextButton.icon(
                            onPressed: _busy ? null : _showConnectionSettings,
                            icon: const Icon(Icons.settings_ethernet_rounded, size: 18),
                            label: const Text('Connection settings'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
