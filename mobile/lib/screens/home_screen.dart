import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../services/api_client.dart';
import '../services/device_bridge.dart';
import '../services/geofence_bridge.dart';
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
  bool loading = true;
  int tab = 0;

  bool get profileComplete {
    final profile = data?['profile'];
    return profile is Map && profile['complete'] == true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadEmail();
    load();
  }

  Future<void> _loadEmail() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => email = p.getString('user_email'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      permissions = await DeviceBridge().status();
      data = await ApiClient().getJson('/bootstrap');
      if (!profileComplete) {
        try { await GeofenceBridge().clear(); } catch (_) {}
        if (mounted) tab = 1;
      } else if (permissions?.ready == true) {
        await registerGeofences();
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> registerGeofences() async {
    if (!profileComplete || data == null || permissions?.ready != true) return;
    final projects = (data!['projects'] as List? ?? const [])
        .map((x) => ProjectGeofence.fromJson(Map<String, dynamic>.from(x as Map)))
        .toList();
    final p = await SharedPreferences.getInstance();
    final token = p.getString('token');
    final device = p.getString('device_uuid');
    if (token == null || device == null) return;
    await GeofenceBridge().register(projects: projects, bearerToken: token, deviceUuid: device);
  }

  Future<void> refreshPermissions({bool register = false}) async {
    try {
      final s = await DeviceBridge().status();
      if (mounted) setState(() => permissions = s);
      if (register && s.ready) await registerGeofences();
    } catch (_) {}
  }

  Future<void> signOut() async {
    await ApiClient().logout();
    try { await GeofenceBridge().clear(); } catch (_) {}
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Widget statusRow(String label, bool ok, {String? action, VoidCallback? onTap}) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: ok ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error),
    title: Text(label),
    trailing: !ok && action != null ? TextButton(onPressed: onTap, child: Text(action)) : null,
  );

  Widget attendanceTab() {
    final colors = Theme.of(context).colorScheme;
    if (!profileComplete) {
      return ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          Icon(Icons.assignment_ind_outlined, size: 52, color: colors.primary),
          const SizedBox(height: 12),
          Text('Complete your Site Access profile', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Automatic attendance and project geofences will be enabled after your profile is created in Airtable.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => setState(() => tab = 1), child: const Text('Open My Profile')),
        ]))),
      ]);
    }

    final open = (data?['open_sessions'] as List?) ?? const [];
    final projects = (data?['projects'] as List?) ?? const [];
    String? active;
    if (open.isNotEmpty) {
      final session = Map<String, dynamic>.from(open.first as Map);
      final p = session['project'];
      if (p is Map) active = '${p['project_code'] ?? ''} · ${p['name'] ?? ''}';
    }
    final ps = permissions;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), children: [
        if (loading) const LinearProgressIndicator(),
        if (email != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(email!, style: TextStyle(color: colors.onSurfaceVariant))),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(open.isEmpty ? 'Not checked in' : 'Checked in', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(open.isEmpty ? 'Automatic check-in will occur when you enter an assigned site.' : active ?? 'Attendance session active', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('${projects.length} assigned ${projects.length == 1 ? 'site' : 'sites'} loaded'),
        ]))),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Background attendance setup', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          statusRow('Precise location', ps?.fineLocation == true, action: 'Allow', onTap: () async { await DeviceBridge().requestFineLocation(); await refreshPermissions(register: true); }),
          statusRow('Allow location all the time', ps?.backgroundLocation == true, action: 'Settings', onTap: () => DeviceBridge().openAppSettings()),
          statusRow('Location services', ps?.locationServices == true, action: 'Turn on', onTap: () => DeviceBridge().openLocationSettings()),
          statusRow('Notifications', ps?.notifications == true, action: 'Allow', onTap: () async { await DeviceBridge().requestNotifications(); await refreshPermissions(); }),
        ]))),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!, style: TextStyle(color: colors.error))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tab == 0 ? 'Site Attendance' : 'My Profile'),
      actions: [IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh_rounded)), IconButton(onPressed: signOut, icon: const Icon(Icons.logout_rounded))],
    ),
    body: IndexedStack(index: tab, children: [attendanceTab(), SiteStaffProfileScreen(onProfileSaved: () async { await load(); if (mounted && profileComplete) setState(() => tab = 0); })]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (index) => setState(() => tab = index),
      destinations: const [NavigationDestination(icon: Icon(Icons.location_on_outlined), selectedIcon: Icon(Icons.location_on), label: 'Attendance'), NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge), label: 'My Profile')],
    ),
  );
}
