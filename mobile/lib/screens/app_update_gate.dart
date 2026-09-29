import 'package:flutter/material.dart';

import '../config.dart';
import '../services/app_update_service.dart';

class AppUpdateGate extends StatefulWidget {
  final Widget child;

  const AppUpdateGate({super.key, required this.child});

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  final _service = AppUpdateService();
  AppRelease? _release;
  bool _checking = true;
  bool _downloading = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final release = await _service.check();
      if (mounted) setState(() => _release = release);
    } catch (_) {
      // An update-server outage must not lock users out of attendance.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _update() async {
    final release = _release;
    if (release == null) return;
    setState(() => _downloading = true);
    try {
      await _service.downloadAndInstall(release);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Download started. Approve the Android installation when prompted.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to start the update. Please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (release == null || !release.updateAvailable || (_dismissed && !release.mandatory)) {
      return widget.child;
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.system_update_alt, size: 64, color: Color(0xff17365d)),
                    const SizedBox(height: 18),
                    Text(
                      release.mandatory ? 'Update required' : 'New update available',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text('Version ${release.versionName} is available. You have ${AppConfig.appVersion}.'),
                    if (release.releaseNotes.trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xfff2f5f9), borderRadius: BorderRadius.circular(14)),
                        child: Text(release.releaseNotes),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _downloading ? null : _update,
                        icon: _downloading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download),
                        label: Text(_downloading ? 'Starting download…' : 'Update now'),
                      ),
                    ),
                    if (!release.mandatory) ...[
                      const SizedBox(height: 10),
                      TextButton(onPressed: () => setState(() => _dismissed = true), child: const Text('Remind me later')),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
