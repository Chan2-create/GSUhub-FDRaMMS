import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/data_record.dart';
import '../../../../core/utils/record_converters.dart';

/// A day no work is scheduled on (2026-11-26): kept by the administrator in
/// Settings → Holidays, because the Philippine holidays move every year and
/// nothing about them is fixed in the app. Saturdays and Sundays are never
/// working days and need no entry.
@immutable
class Holiday {
  Holiday({required DateTime day, required this.name}) : day = _dateOnly(day);

  factory Holiday.fromRecord(DataRecord record) {
    final raw = record.fields['day'];
    final day = switch (raw) {
      final DateTime value => value,
      final String value => DateTime.parse(value),
      _ => DateTime.parse(record.id),
    };
    return Holiday(
      day: day,
      name: RecordConverters.require<String>(record.fields, 'name'),
    );
  }

  /// The calendar day, without a time.
  final DateTime day;

  /// "Bonifacio Day".
  final String name;

  /// The day as the database stores it: `2026-11-30`.
  String get id => DateFormat('yyyy-MM-dd').format(day);

  static DateTime _dateOnly(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  @override
  bool operator ==(Object other) =>
      other is Holiday && other.day == day && other.name == name;

  @override
  int get hashCode => Object.hash(day, name);

  @override
  String toString() => 'Holiday($id, $name)';
}
