import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import '../models/department.dart';
import 'department_repository.dart';

/// Supabase-backed [DepartmentRepository]. Read from the table, which
/// anyone may read; changed only through the database's functions, by an
/// administrator.
class DepartmentRepositoryImpl extends SupabaseRepository
    implements DepartmentRepository {
  const DepartmentRepositoryImpl({
    required super.client,
    required super.guard,
    super.live,
  });

  static const String _table = 'departments';

  @override
  Future<Result<List<Department>>> getActive() => getMany(
    query: client
        .from(_table)
        .select()
        .eq('is_active', true)
        .order('name', ascending: true),
    convert: Department.fromRecord,
  );

  @override
  Stream<Result<List<Department>>> watchAll() => watchMany(
    stream: liveRows(_table, (rows) => rows.order('name', ascending: true)),
    convert: Department.fromRecord,
  );

  @override
  Future<Result<String>> create(String name) =>
      rpcOnce<String>('create_department', {'name': name});

  @override
  Future<Result<void>> rename(String id, String name) =>
      rpc('rename_department', {'id': id, 'name': name});

  @override
  Future<Result<void>> setActive(String id, {required bool active}) =>
      rpc('set_department_active', {'id': id, 'active': active});
}
