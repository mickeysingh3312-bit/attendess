import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

const attendanceTimezone = 'Australia/Sydney';

late final timezone.Location _sydney;
bool _initialized = false;

void initializeSydneyTime() {
  if (_initialized) return;
  timezone_data.initializeTimeZones();
  _sydney = timezone.getLocation(attendanceTimezone);
  timezone.setLocalLocation(_sydney);
  _initialized = true;
}

class SydneyTime {
  static timezone.TZDateTime now() {
    _ensureInitialized();
    return timezone.TZDateTime.now(_sydney);
  }

  static timezone.TZDateTime? parse(Object? value) {
    if (value == null) return null;
    _ensureInitialized();

    final parsed = value is DateTime
        ? value
        : DateTime.tryParse(value.toString());
    if (parsed == null) return null;

    return timezone.TZDateTime.from(parsed.toUtc(), _sydney);
  }

  static void _ensureInitialized() {
    if (!_initialized) initializeSydneyTime();
  }
}
