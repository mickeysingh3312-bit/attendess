import 'package:flutter/material.dart';

import '../services/api_client.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  String period = 'today';
  Map<String, dynamic>? data;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final result = await ApiClient().getJson('/attendance/today?period=$period');
      if (mounted) setState(() => data = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _friendlyError(e);
        });
      }
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
      return 'History could not be refreshed. Check your internet connection and try again.';
    }
    return text;
  }

  List<Map<String, dynamic>> get sessions => (data?['sessions'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();

  int get totalSeconds {
    final summary = data?['summary'];
    if (summary is Map) {
      final parsed = int.tryParse('${summary['total_seconds'] ?? ''}');
      if (parsed != null) return parsed;
    }
    return sessions.fold<int>(0, (total, item) {
      return total + (int.tryParse('${item['duration_seconds'] ?? 0}') ?? 0);
    });
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _time(Object? value) {
    final date = _date(value);
    if (date == null) return '—';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${_two(date.minute)} $suffix';
  }

  String _day(Object? value) {
    final date = _date(value);
    if (date == null) return 'Unknown date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(date.year, date.month, date.day);
    if (sessionDay == today) return 'Today';
    if (sessionDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _duration(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  Future<void> _changePeriod(String value) async {
    if (period == value) return;
    setState(() {
      period = value;
      data = null;
    });
    await load();
  }

  Widget _periodButton(String value, String label) {
    final selected = period == value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: selected
            ? FilledButton(
                onPressed: loading ? null : () => _changePeriod(value),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: loading ? null : () => _changePeriod(value),
                child: Text(label),
              ),
      ),
    );
  }

  Widget _summaryCard() {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.schedule_rounded, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _duration(totalSeconds),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${sessions.length} ${sessions.length == 1 ? 'site visit' : 'site visits'}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionCard(Map<String, dynamic> session) {
    final colors = Theme.of(context).colorScheme;
    final project = session['project'] is Map
        ? Map<String, dynamic>.from(session['project'] as Map)
        : <String, dynamic>{};
    final code = (project['project_code'] ?? '').toString().trim();
    final name = (project['name'] ?? 'Project').toString().trim();
    final address = (project['address'] ?? '').toString().trim();
    final open = (session['status'] ?? '').toString() == 'open' || session['check_out_at'] == null;
    final duration = int.tryParse('${session['duration_seconds'] ?? 0}') ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: open ? colors.primaryContainer : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    open ? Icons.location_on_rounded : Icons.business_rounded,
                    color: open ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code.isEmpty ? name : '$code · $name',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (open)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _timeBlock('CHECK IN', _time(session['check_in_at'])),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 18),
                Expanded(
                  child: _timeBlock('CHECK OUT', open ? 'In progress' : _time(session['check_out_at'])),
                ),
                Expanded(
                  child: _timeBlock('DURATION', open ? '${_duration(duration)}+' : _duration(duration)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeBlock(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Column(
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
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final session in sessions) {
      grouped.putIfAbsent(_day(session['check_in_at']), () => []).add(session);
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          if (loading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Row(
            children: [
              _periodButton('today', 'Today'),
              _periodButton('week', 'Week'),
              _periodButton('month', 'Month'),
            ],
          ),
          const SizedBox(height: 14),
          if (data != null) _summaryCard(),
          if (error != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.cloud_off_rounded, color: colors.error),
                    const SizedBox(width: 12),
                    Expanded(child: Text(error!)),
                    TextButton(onPressed: loading ? null : load, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          ],
          if (!loading && error == null && sessions.isEmpty) ...[
            const SizedBox(height: 28),
            Icon(Icons.event_available_outlined, size: 58, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              'No attendance recorded for this period.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          for (final group in grouped.entries) ...[
            const SizedBox(height: 20),
            Text(
              group.key,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            for (final session in group.value) ...[
              _sessionCard(session),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}
