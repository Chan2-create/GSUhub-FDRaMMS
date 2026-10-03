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

  group('dayAndTime — the timeline (Figma 169:1064, 3.B)', () {
    String dayAndTime(DateTime when) => RelativeTime.dayAndTime(when, now: now);

    test('today and yesterday by name', () {
      expect(dayAndTime(DateTime(2026, 10, 1, 9, 45)), 'Today, 09:45 AM');
      expect(dayAndTime(DateTime(2026, 9, 30, 16, 30)), 'Yesterday, 04:30 PM');
    });

    test('older by date, with the year once it differs', () {
      expect(dayAndTime(DateTime(2026, 9, 25, 14, 15)), 'Sep 25, 02:15 PM');
      expect(dayAndTime(DateTime(2025, 12, 3, 8)), 'Dec 3, 2025, 08:00 AM');
    });
  });

  group('ago — Notifications (Figma 169:1459, 3.B)', () {
    String ago(DateTime when) => RelativeTime.ago(when, now: now);

    test('in words through today', () {
      expect(ago(now.subtract(const Duration(seconds: 20))), 'Just now');
      expect(ago(now.subtract(const Duration(minutes: 1))), '1 minute ago');
      expect(ago(now.subtract(const Duration(minutes: 45))), '45 minutes ago');
      expect(ago(now.subtract(const Duration(hours: 1))), '1 hour ago');
      expect(ago(now.subtract(const Duration(hours: 5))), '5 hours ago');
    });

    test('before today, the day and time', () {
      expect(ago(DateTime(2026, 9, 30, 16, 30)), 'Yesterday, 04:30 PM');
      expect(ago(DateTime(2026, 9, 24, 10, 15)), 'Sep 24, 10:15 AM');
    });
  });
}
