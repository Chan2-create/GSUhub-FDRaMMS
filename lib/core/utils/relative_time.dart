import 'package:intl/intl.dart';

/// "How long ago", as the faculty and staff home screen writes it on a
/// recent report (Figma `170:2050`): "3H AGO", "YESTERDAY", then the date —
/// "May 24", with the year once it is not this one.
abstract final class RelativeTime {
  static final DateFormat _sameYear = DateFormat('MMM d');
  static final DateFormat _otherYear = DateFormat('MMM d, y');

  /// [when] relative to [now] (the current time by default). Both are read
  /// in local time, so "yesterday" follows the device's calendar.
  static String stamp(DateTime when, {DateTime? now}) {
    final local = when.toLocal();
    final current = (now ?? DateTime.now()).toLocal();
    final elapsed = current.difference(local);

    // A clock slightly behind the server's can put a fresh report in the
    // future; it is still "just now".
    if (elapsed.inMinutes < 1) return 'JUST NOW';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}M AGO';

    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) return '${elapsed.inHours}H AGO';
    if (day == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return (local.year == current.year ? _sameYear : _otherYear).format(local);
  }

  static final DateFormat _clock = DateFormat('hh:mm a');

  /// The day and time above a timeline entry (Figma `169:1064`): "Today,
  /// 09:45 AM", "Yesterday, 04:30 PM", "Oct 25, 02:15 PM", with the year
  /// once it is not this one.
  static String dayAndTime(DateTime when, {DateTime? now}) {
    final local = when.toLocal();
    final current = (now ?? DateTime.now()).toLocal();
    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(local.year, local.month, local.day);

    final String date;
    if (day == today) {
      date = 'Today';
    } else if (day == today.subtract(const Duration(days: 1))) {
      date = 'Yesterday';
    } else {
      date = (local.year == current.year ? _sameYear : _otherYear).format(
        local,
      );
    }
    return '$date, ${_clock.format(local)}';
  }
}
