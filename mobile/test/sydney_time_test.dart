import 'package:flutter_test/flutter_test.dart';
import 'package:five_star_attendance/utils/sydney_time.dart';

void main() {
  setUpAll(initializeSydneyTime);

  test('converts UTC timestamps to Sydney standard time', () {
    final date = SydneyTime.parse('2026-06-15T00:00:00Z');

    expect(date, isNotNull);
    expect(date!.hour, 10);
    expect(date.timeZoneOffset, const Duration(hours: 10));
  });

  test('converts UTC timestamps to Sydney daylight time', () {
    final date = SydneyTime.parse('2026-12-15T00:00:00Z');

    expect(date, isNotNull);
    expect(date!.hour, 11);
    expect(date.timeZoneOffset, const Duration(hours: 11));
  });
}
