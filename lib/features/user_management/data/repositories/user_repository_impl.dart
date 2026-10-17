import '../../../../core/data/supabase_repository.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/app_user.dart';
import 'user_repository.dart';

/// Supabase-backed [UserRepository] (Objective 1).
///
/// Reads come from `users` under row level security: one's own row, or
/// every row for an administrator. Writes are the account functions
/// (supabase/migrations/*_account_functions.sql), which check the caller,
/// refuse the lock-outs, and write the audit entry under the caller's own
/// name — so the `actor` the interface passes is not sent.
class UserRepositoryImpl extends SupabaseRepository implements UserRepository {
  const UserRepositoryImpl({required super.client, required super.guard});

  static const String _table = 'users';

  @override
  Future<Result<AppUser>> getById(String uid) =>
      getOne(table: _table, id: uid, convert: AppUser.fromFirestore);

  @override
  Stream<Result<AppUser>> watchById(String uid) =>
      watchOne(table: _table, id: uid, convert: AppUser.fromFirestore);

  @override
  Future<Result<List<AppUser>>> getAll({UserRole? role}) {
    final query = client.from(_table).select();
    return getMany(
      query: role == null ? query : query.eq('role', role.id),
      convert: AppUser.fromFirestore,
    );
  }

  @override
  Stream<Result<List<AppUser>>> watchAll() => watchMany(
    stream: client.from(_table).stream(primaryKey: const ['id']),
    convert: AppUser.fromFirestore,
  );

  @override
  Future<Result<List<AppUser>>> getPersonnel({
    String? specializationId,
    PersonnelAvailability? availability,
  }) {
    var query = client
        .from(_table)
        .select()
        .eq('role', UserRole.maintenancePersonnel.id);
    if (specializationId != null) {
      query = query.eq('specialization', specializationId);
    }
    if (availability != null) {
      query = query.eq('availability', availability.id);
    }
    return getMany(query: query, convert: AppUser.fromFirestore);
  }

  @override
  Stream<Result<List<AppUser>>> watchPersonnel() =>
      // Filtered here, not by the stream: a role can change, and Realtime
      // never tells a stream filtered on it about a row that left.
      watchAll().map(
        (result) => result.map(
          (users) => [
            for (final user in users)
              if (user.role == UserRole.maintenancePersonnel) user,
          ],
        ),
      );

  @override
  Future<Result<void>> create(AppUser user) =>
      SupabaseRepository.unsupported('UserRepository.create');

  @override
  Future<Result<void>> update(AppUser user) =>
      SupabaseRepository.unsupported('UserRepository.update');

  @override
  Future<Result<void>> createSelfRegistration(AppUser user) =>
      // Once: a retry after a first attempt that landed would be refused
      // as a duplicate and hide that the sign-up worked.
      rpcOnce<void>('register_self', {
        'full_name': user.fullName,
        'department': user.department,
        'contact_number': user.contactNumber,
      });

  @override
  Future<Result<void>> createAccount({
    required AppUser user,
    required AuditActor actor,
  }) => rpcOnce<void>('create_account', {
    'id': user.id,
    'full_name': user.fullName,
    'email': user.email,
    'role': user.role.id,
    'account_status': user.accountStatus.id,
    'department': user.department,
    'contact_number': user.contactNumber,
    'specialization': user.specialization?.id,
    'availability': user.availability?.id,
  });

  @override
  Future<Result<void>> updateAccount({
    required AppUser updated,
    required AuditActor actor,
  }) => rpc('update_account', {
    'id': updated.id,
    'full_name': updated.fullName,
    'role': updated.role.id,
    'department': updated.department,
    'contact_number': updated.contactNumber,
    'specialization': updated.specialization?.id,
    'availability': updated.availability?.id,
  });

  @override
  Future<Result<void>> setAccountStatus(
    String uid,
    AccountStatus status, {
    required AuditActor actor,
  }) => rpc('set_account_status', {'id': uid, 'status': status.id});

  @override
  Future<Result<void>> setAvailability(
    String uid,
    PersonnelAvailability availability,
  ) => SupabaseRepository.unsupported('UserRepository.setAvailability');

  /// The database keeps the count as work orders are assigned and
  /// completed (app.assign_work_order, app.move_work_order).
  @override
  Future<Result<void>> adjustActiveTaskCount(String uid, int delta) =>
      SupabaseRepository.unsupported('UserRepository.adjustActiveTaskCount');

  @override
  Future<Result<void>> setFcmToken(String uid, String? token) =>
      rpc('set_fcm_token', {'id': uid, 'token': token});
}
