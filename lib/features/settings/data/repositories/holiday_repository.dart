import '../../../../core/utils/result.dart';
import '../models/holiday.dart';

/// The holidays list (2026-11-26,
/// supabase/migrations/*_scheduling_holidays_and_labels.sql): the days no
/// work is scheduled on, besides Saturdays and Sundays.
abstract interface class HolidayRepository {
  /// Every holiday, by date, live.
  Stream<Result<List<Holiday>>> watchAll();

  /// Adds [name] on [day]. Refused when the day already has one.
  Future<Result<void>> add(DateTime day, String name);

  /// Takes [day] off the list: it is a working day again, if a weekday.
  Future<Result<void>> remove(DateTime day);
}
