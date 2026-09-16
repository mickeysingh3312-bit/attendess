import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../services/api_client.dart';
import '../services/device_bridge.dart';
import '../services/geofence_bridge.dart';
import 'attendance_history_screen.dart';
import 'login_screen.dart';
import 'site_staff_profile_screen.dart';

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
  DateTime? lastSync;
  bool loading = true;
  int tab = 0;
  Timer? clockTimer;

  bool get profileComplete {
    final profile = data?['profile'];
    return profile is Map && profile['complete'] == true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLocalState();
    load();
    clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadLocalState() async {
    final preferences = await SharedPreferences.getInstance();
    final savedSync = preferences.getString('last_server_sync_at');
    if (!mounted) return;
    setState(() {
      email = preferences.getString('user_email');
      lastSync = savedSync == null ? null : DateTime.tryParse(savedSync)?.toLocal();
    });
  }

  Future<void> _markSynced() async {
    final now = DateTime.now();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('last_server_sync_at', now.toUtc().toIso8601String());
    if (mounted) setState(() => lastSync = now);
  }

  @override
  void dispose() {
    clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
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
      await _markSynced();

      if (!profileComplete) {
        try {
          await GeofenceBridge().clear();
        } catch (_) {}
        if (mounted) tab = 2;
      } else if (permissions?.ready == true) {
        await registerGeofences();
      }
    } catch (e) {
      error = _friendlyError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _friendlyError(Object value) {
    final text = value.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('timed out') ||
        text.contains('TimeoutException')) {
      return 'You appear to be offline. Automatic attendance events will retry when your connection returns.';
    }
    return text;
  }

  Future<void> registerGeofences() async {
    if (!profileComplete || data == null || permissions?.ready != true) return;
    final projects = (data!['projects'] as List? ?? const [])
        .map((item) => ProjectGeofence.fromJson(Map<String, dynamic>.from(item as Map)))
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

  Future<void> refreshPermissions({bool register = false}) async {
    try {
      final status = await DeviceBridge().status();
      if (mounted) setState(() => permissions = status);
      if (register && status.ready) await registerGeofences();
    } catch (_) {}
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

  List<Map<String, dynamic>> get openSessions =>
      (data?['open_sessions'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  List<Map<String, dynamic>> get projects =>
      (data?['projects'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  String get firstName {
    final user = data?['user'];
    if (user is Map) {
      final name = (user['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
    }
    return '';
  }

  String greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _time(Object? value) {
    final date = _date(value);
    if (date == null) return '—';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${date.minute.toString().padLeft(2, '0')} $suffix';
  }

  String _duration(DateTime? start) {
    if (start == null) return '—';
    final difference = DateTime.now().difference(start);
    final seconds = difference.inSeconds < 0 ? 0 : difference.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  String _relativeSync() {
    if (lastSync == null) return 'Not synced yet';
    final difference = DateTime.now().difference(lastSync!);
    if (difference.inSeconds < 30) return 'Just now';
    if (difference.inMinutes < 2) return '1 minute ago';
    if (difference.inMinutes < 60) return '${difference.inMinutes} minutes ago';
    return _time(lastSync!.toIso8601String());
  }

  Widget statusRow(
    String label,
    bool ok, {
    String? detail,
    String? action,
    VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 32,
      leading: Icon(
        ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
        color: ok ? colors.primary : colors.error,
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: detail == null ? null : Text(detail),
      trailing: !ok && action != null
          ? TextButton(onPressed: onTap, child: Text(action))
          : null,
    );
  }

  Widget _profileRequired() {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Icon(Icons.assignment_ind_outlined, size: 56, color: colors.primary),
                const SizedBox(height: 14),
                Text(
                  'Complete your Site Access profile',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Automatic attendance becomes active after your required Site Access Staff details are complete.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => setState(() => tab = 2),
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Complete My Profile'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _todayStatusCard() {
    final colors = Theme.of(context).colorScheme;
    final open = openSessions;
    final active = open.isNotEmpty ? open.first : null;
    final project = active?['project'] is Map
        ? Map<String, dynamic>.from(active!['project'] as Map)
        : <String, dynamic>{};
    final code = (project['project_code'] ?? '').toString().trim();
    final name = (project['name'] ?? '').toString().trim();
    final checkIn = _date(active?['check_in_at']);
    final checkedIn = active != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: checkedIn ? colors.primaryContainer : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    checkedIn ? Icons.location_on_rounded : Icons.location_off_outlined,
                    color: checkedIn ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        checkedIn ? 'Checked In' : 'Not currently on site',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        checkedIn
                            ? (code.isEmpty ? name : '$code · $name')
                            : 'Check-in happens automatically at an assigned site.',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (checkedIn) ...[
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(child: _metric('CHECKED IN', _time(active['check_in_at']))),
                  const SizedBox(width: 10),
                  Expanded(child: _metric('DURATION', _duration(checkIn))),
                ],
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => tab = 1),
                icon: const Icon(Icons.history_rounded),
                label: const Text("View Today's Attendance"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _trackingHealthCard() {
    final colors = Theme.of(context).colorScheme;
    final status = permissions;
    final healthy = status?.healthy == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tracking Health',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: healthy ? colors.primaryContainer : colors.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    healthy ? 'READY' : 'ACTION NEEDED',
                    style: TextStyle(
                      color: healthy ? colors.onPrimaryContainer : colors.onErrorContainer,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            statusRow(
              'Precise location',
              status?.fineLocation == true,
              detail: status?.fineLocation == true ? 'Allowed' : 'Required for site detection',
              action: 'Allow',
              onTap: () async {
                await DeviceBridge().requestFineLocation();
                await refreshPermissions(register: true);
              },
            ),
            statusRow(
              'Background location',
              status?.backgroundLocation == true,
              detail: status?.backgroundLocation == true ? 'Always allowed' : 'Set location to Allow all the time',
              action: 'Settings',
              onTap: () => DeviceBridge().openAppSettings(),
            ),
            statusRow(
              'Location services',
              status?.locationServices == true,
              detail: status?.locationServices == true ? 'GPS is available' : 'Turn on device location',
              action: 'Turn on',
              onTap: () => DeviceBridge().openLocationSettings(),
            ),
            statusRow(
              'Notifications',
              status?.notifications == true,
              detail: status?.notifications == true ? 'Attendance alerts enabled' : 'Allow check-in/out alerts',
              action: 'Allow',
              onTap: () async {
                await DeviceBridge().requestNotifications();
                await refreshPermissions();
              },
            ),
            statusRow(
              'Battery optimisation',
              status?.batteryOptimizationDisabled == true,
              detail: status?.batteryOptimizationDisabled == true
                  ? 'Background tracking is unrestricted'
                  : 'Disable optimisation for reliable background tracking',
              action: 'Fix',
              onTap: () => DeviceBridge().openBatterySettings(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _syncCard() {
    final colors = Theme.of(context).colorScheme;
    final offline = error != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: offline ? colors.errorContainer : colors.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                offline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                color: offline ? colors.onErrorContainer : colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    offline ? 'Connection unavailable' : 'Everything up to date',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    offline
                        ? 'Attendance events retry automatically when internet returns.'
                        : 'Last server sync: ${_relativeSync()}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _assignedSitesCard() {
    final colors = Theme.of(context).colorScheme;
    final items = projects.take(3).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Assigned Sites',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text(
                  '${projects.length}',
                  style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (items.isEmpty) ...[
              const SizedBox(height: 14),
              Text('No active sites are currently assigned.', style: TextStyle(color: colors.onSurfaceVariant)),
            ],
            for (final project in items) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.business_outlined, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _projectLabel(project),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if ((project['address'] ?? '').toString().trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            project['address'].toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _projectLabel(Map<String, dynamic> project) {
    final code = (project['project_code'] ?? '').toString().trim();
    final name = (project['name'] ?? 'Project').toString().trim();
    return code.isEmpty ? name : '$code · $name';
  }

  Widget attendanceTab() {
    if (!profileComplete) return _profileRequired();

    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          if (loading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            '${greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            email ?? 'Five Star Attendance',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          _todayStatusCard(),
          const SizedBox(height: 14),
          _syncCard(),
          const SizedBox(height: 14),
          _trackingHealthCard(),
          const SizedBox(height: 14),
          _assignedSitesCard(),
          if (error != null) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: colors.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(error!)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Attendance', 'History', 'My Profile'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[tab]),
        actions: [
          if (tab == 0)
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
      body: IndexedStack(
        index: tab,
        children: [
          attendanceTab(),
          const AttendanceHistoryScreen(),
          SiteStaffProfileScreen(
            onProfileSaved: () async {
              await load();
              if (mounted && profileComplete) setState(() => tab = 0);
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
