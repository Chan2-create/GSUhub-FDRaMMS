import 'dart:async';

import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/settings/data/models/holiday.dart';
import 'package:gsuhub/features/settings/data/repositories/holiday_repository.dart';

/// The holidays list, in memory and live (2026-11-26): what the date
/// pickers leave out and Settings → Holidays keeps. As the database, one
/// holiday a day.
class FakeHolidayRepository implements HolidayRepository {
  FakeHolidayRepository([Iterable<Holiday> holidays = const []])
    : _byDay = {for (final holiday in holidays) holiday.day: holiday};

  final Map<DateTime, Holiday> _byDay;
  final _changes = StreamController<void>.broadcast();

  List<Holiday> get all =>
      _byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));

  @override
  Stream<Result<List<Holiday>>> watchAll() async* {
    yield Result.success(all);
    await for (final _ in _changes.stream) {
      yield Result.success(all);
    }
  }

  @override
  Future<Result<void>> add(DateTime day, String name) async {
    final holiday = Holiday(day: day, name: name.trim());
    if (_byDay.containsKey(holiday.day)) {
      return const Result.failure(
        ValidationFailure('That day is already a holiday.'),
      );
    }
    _byDay[holiday.day] = holiday;
    _changes.add(null);
    return const Result.success(null);
  }

  @override
  Future<Result<void>> remove(DateTime day) async {
    _byDay.remove(DateTime(day.year, day.month, day.day));
    _changes.add(null);
    return const Result.success(null);
  }
}
