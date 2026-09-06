import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../services/api_client.dart';
import '../services/device_bridge.dart';
import '../services/geofence_bridge.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? data;
  DevicePermissionStatus? permissions;
  String? error;
  String? email;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadEmail();
    load();
  }

  Future<void> _loadEmail() async {
    final preferences = await SharedPreferences.getInstance();
    if (mounted) setState(() => email = preferences.getString('user_email'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshPermissions(register: true);
      load();
    }
  }

  Future<void> refreshPermissions({bool register = false}) async {
    try {
      final status = await DeviceBridge().status();
      if (mounted) setState(() => permissions = status);
      if (register && status.ready && data != null) await registerGeofences();
    } catch (_) {}
  }

  Future<void> registerGeofences() async {
    if (data == null || permissions?.ready != true) return;
    final projects = (data!['projects'] as List? ?? const [])
        .map((item) => ProjectGeofence.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString('token');
    final device = preferences.getString('device_uuid');
    if (token == null || device == null) return;
    await GeofenceBridge().register(
      projects: projects,
      bearerToken: token,
      deviceUuid: device,
    );
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      permissions = await DeviceBridge().status();
      data = await ApiClient().getJson('/bootstrap');
      if (permissions?.ready == true) await registerGeofences();
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> signOut() async {
    await ApiClient().logout();
    try {
      await GeofenceBridge().clear();
    } catch (_) {}
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('token');
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  Widget statusRow(
    String label,
    bool ok, {
    String? action,
    VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
        color: ok ? colors.primary : colors.error,
      ),
      title: Text(label),
      trailing: !ok && action != null
          ? TextButton(onPressed: onTap, child: Text(action))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = (data?['open_sessions'] as List?) ?? const [];
    final projects = (data?['projects'] as List?) ?? const [];
    final projectCount = projects.length;
    final permissionStatus = permissions;
    final colors = Theme.of(context).colorScheme;

    String? activeProject;
    if (open.isNotEmpty) {
      final session = Map<String, dynamic>.from(open.first as Map);
      final project = session['project'];
      if (project is Map) {
        final map = Map<String, dynamic>.from(project);
        activeProject = '${map['project_code'] ?? ''} · ${map['name'] ?? ''}'.trim();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Site Attendance'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            if (loading) const LinearProgressIndicator(),
            if (email != null) ...[
              const SizedBox(height: 12),
              Text(
                email!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: open.isEmpty
                                ? colors.surfaceContainerHighest
                                : colors.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            open.isEmpty
                                ? Icons.location_off_outlined
                                : Icons.location_on_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            open.isEmpty ? 'Not checked in' : 'Checked in',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      open.isEmpty
                          ? 'Automatic check-in will occur when you enter an assigned site.'
                          : activeProject ?? 'Attendance session active',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$projectCount assigned ${projectCount == 1 ? 'site' : 'sites'} loaded',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Background attendance setup',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'All required permissions must remain enabled for automatic site entry and exit.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    statusRow(
                      'Precise location',
                      permissionStatus?.fineLocation == true,
                      action: 'Allow',
                      onTap: () async {
                        await DeviceBridge().requestFineLocation();
                        await refreshPermissions(register: true);
                      },
                    ),
                    statusRow(
                      'Allow location all the time',
                      permissionStatus?.backgroundLocation == true,
                      action: 'Settings',
                      onTap: () => DeviceBridge().openAppSettings(),
                    ),
                    statusRow(
                      'Location services',
                      permissionStatus?.locationServices == true,
                      action: 'Turn on',
                      onTap: () => DeviceBridge().openLocationSettings(),
                    ),
                    statusRow(
                      'Notifications',
                      permissionStatus?.notifications == true,
                      action: 'Allow',
                      onTap: () async {
                        await DeviceBridge().requestNotifications();
                        await refreshPermissions();
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  error!,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
