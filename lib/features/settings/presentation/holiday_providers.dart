import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/working_day_picker.dart';
import '../data/models/holiday.dart';

/// Every holiday, by date, live (2026-11-26): Settings → Holidays, and the
/// days the scheduling date pickers leave out.
final holidaysProvider = StreamProvider<Result<List<Holiday>>>(
  (ref) => ref.watch(holidayRepositoryProvider).watchAll(),
);

/// The one way the console picks a scheduling date (the report's schedule,
/// a work order's target date and its rescheduling, a task's due date):
/// [showWorkingDayPicker] with the administrator's holidays. Holidays that
/// cannot be read leave the weekends out still; the database refuses a
/// holiday anyway.
Future<DateTime?> pickSchedulingDay(
  BuildContext context,
  WidgetRef ref, {
  DateTime? initial,
  String? helpText,
}) async {
  // Listened while it is read: a provider nothing listens to is paused,
  // and its first list would never arrive.
  final listening = ref.listenManual(holidaysProvider, (_, _) {});
  final Result<List<Holiday>> read;
  try {
    read = await ref.read(holidaysProvider.future);
  } finally {
    listening.close();
  }
  final holidays = switch (read) {
    Success(:final value) => {for (final holiday in value) holiday.day},
    Error() => <DateTime>{},
  };
  if (!context.mounted) return null;
  return showWorkingDayPicker(
    context,
    holidays: holidays,
    initial: initial,
    helpText: helpText,
  );
}
