import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/utils/relative_time.dart';

/// The home screen's "3H AGO" / "YESTERDAY" / "May 24" (Figma `170:2050`).
void main() {
  final now = DateTime(2026, 10, 1, 15, 30);

  String stamp(DateTime when) => RelativeTime.stamp(when, now: now);

  test('under a minute, and a little in the future, is just now', () {
    expect(stamp(now.subtract(const Duration(seconds: 20))), 'JUST NOW');
    expect(stamp(now.add(const Duration(seconds: 30))), 'JUST NOW');
  });

  test('minutes, then hours, within the same day', () {
    expect(stamp(now.subtract(const Duration(minutes: 12))), '12M AGO');
    expect(stamp(now.subtract(const Duration(hours: 3))), '3H AGO');
  });

  test('the previous calendar day is yesterday', () {
    expect(stamp(DateTime(2026, 9, 30, 9)), 'YESTERDAY');
  });

  test('older dates read as the date, with the year once it differs', () {
    expect(stamp(DateTime(2026, 5, 24, 10)), 'May 24');
    expect(stamp(DateTime(2025, 12, 3)), 'Dec 3, 2025');
  });
}
