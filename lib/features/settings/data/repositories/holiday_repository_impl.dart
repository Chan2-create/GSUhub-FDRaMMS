import 'package:intl/intl.dart';

import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import '../models/holiday.dart';
import 'holiday_repository.dart';

/// Supabase-backed [HolidayRepository]. Read from the table, which every
/// active account may read; changed only through the database's functions,
/// by an administrator.
class HolidayRepositoryImpl extends SupabaseRepository
    implements HolidayRepository {
  const HolidayRepositoryImpl({
    required super.client,
    required super.guard,
    super.live,
  });

  static const String _table = 'holidays';

  static String _dayOf(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

  @override
  Stream<Result<List<Holiday>>> watchAll() => watchMany(
    stream: liveRows(_table, (rows) => rows.order('day', ascending: true)),
    convert: Holiday.fromRecord,
  );

  @override
  Future<Result<void>> add(DateTime day, String name) =>
      rpc('add_holiday', {'day': _dayOf(day), 'name': name.trim()});

  @override
  Future<Result<void>> remove(DateTime day) =>
      rpc('remove_holiday', {'day': _dayOf(day)});
}
