import '../../../../core/utils/result.dart';
import '../models/department.dart';

/// The departments and faculties list (2026-11-17,
/// supabase/migrations/*_account_sessions_and_departments.sql).
abstract interface class DepartmentRepository {
  /// The departments on the list now, by name, read once. Works signed
  /// out: the Create Account form lists them before there is an account.
  Future<Result<List<Department>>> getActive();

  /// The whole list, live, retired ones included for an administrator.
  Stream<Result<List<Department>>> watchAll();

  /// Adds [name] to the list. Refused when it is already there, whatever
  /// the case.
  Future<Result<String>> create(String name);

  /// Renames a department, on the accounts that carry it too.
  Future<Result<void>> rename(String id, String name);

  /// Takes a department off the list for new choices, or puts it back.
  Future<Result<void>> setActive(String id, {required bool active});
}
