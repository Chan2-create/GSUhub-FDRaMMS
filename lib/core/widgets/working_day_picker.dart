import 'package:flutter/material.dart';

/// Working days for scheduling (2026-11-26): every scheduling date picker
/// in the console opens through [showWorkingDayPicker], so a Saturday, a
/// Sunday or one of the administrator's holidays cannot be picked
/// anywhere. The database refuses them too (`app.require_working_day`);
/// this is the convenience, not the guard.
abstract final class WorkingDays {
  /// Whether [day] can be a scheduling date: a weekday that is not one of
  /// [holidays] (dates without times).
  static bool isWorkingDay(DateTime day, Set<DateTime> holidays) =>
      day.weekday != DateTime.saturday &&
      day.weekday != DateTime.sunday &&
      !holidays.contains(DateUtils.dateOnly(day));

  /// The first working day on or after [from], up to [last]; null when
  /// there is none in between.
  static DateTime? firstFrom(
    DateTime from,
    Set<DateTime> holidays, {
    required DateTime last,
  }) {
    var day = DateUtils.dateOnly(from);
    final end = DateUtils.dateOnly(last);
    while (!day.isAfter(end)) {
      if (isWorkingDay(day, holidays)) return day;
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return null;
  }
}

/// A date picker that offers working days only: no Saturdays, Sundays or
/// [holidays]. The first offered is [initial] or, if that cannot be picked,
/// the next working day after it — a picker opening on a day it may not
/// show throws. Dates run from [first] (today by default) for [daysAhead]
/// days. Returns the day picked, or null.
Future<DateTime?> showWorkingDayPicker(
  BuildContext context, {
  required Set<DateTime> holidays,
  DateTime? initial,
  DateTime? first,
  int daysAhead = 365,
  String? helpText,
}) {
  final start = DateUtils.dateOnly(first ?? DateTime.now());
  final last = start.add(Duration(days: daysAhead));
  final wanted = initial == null || initial.isBefore(start)
      ? start
      : DateUtils.dateOnly(initial);
  final opening =
      WorkingDays.firstFrom(wanted, holidays, last: last) ??
      WorkingDays.firstFrom(start, holidays, last: last);
  if (opening == null) return Future.value();
  return showDatePicker(
    context: context,
    initialDate: opening,
    firstDate: start,
    lastDate: last,
    helpText: helpText,
    selectableDayPredicate: (day) => WorkingDays.isWorkingDay(day, holidays),
  );
}
