import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../models/app_user.dart';
import 'user_repository.dart';

/// Firestore-backed [UserRepository]. Persistence only.
class UserRepositoryImpl extends FirestoreRepository implements UserRepository {
  const UserRepositoryImpl({required super.db, required super.guard});

  static const String _path = FirestorePaths.users;

  @override
  Future<Result<AppUser>> getById(String uid) =>
      getOne(path: _path, id: uid, convert: AppUser.fromFirestore);

  @override
  Stream<Result<AppUser>> watchById(String uid) =>
      watchOne(path: _path, id: uid, convert: AppUser.fromFirestore);

  @override
  Future<Result<List<AppUser>>> getAll({UserRole? role}) {
    Query<Map<String, dynamic>> query = collection(_path);
    if (role != null) {
      query = query.where('role', isEqualTo: role.id);
    }
    return getMany(query: query, convert: AppUser.fromFirestore);
  }

  @override
  Stream<Result<List<AppUser>>> watchAll() =>
      watchMany(query: collection(_path), convert: AppUser.fromFirestore);

  @override
  Future<Result<List<AppUser>>> getPersonnel({
    String? specializationId,
    PersonnelAvailability? availability,
  }) {
    Query<Map<String, dynamic>> query = collection(_path)
        .where('role', isEqualTo: UserRole.maintenancePersonnel.id);

    if (specializationId != null) {
      query = query.where('specialization', isEqualTo: specializationId);
    }
    if (availability != null) {
      query = query.where('availability', isEqualTo: availability.id);
    }

    return getMany(query: query, convert: AppUser.fromFirestore);
  }

  @override
  Stream<Result<List<AppUser>>> watchPersonnel() => watchMany(
    // A single equality filter needs no composite index. Sorting by name
    // server-side would, so the caller orders the (small) roster instead.
    query: collection(_path)
        .where('role', isEqualTo: UserRole.maintenancePersonnel.id),
    convert: AppUser.fromFirestore,
  );

  @override
  Future<Result<void>> create(AppUser user) =>
      setDoc(path: _path, id: user.id, data: user.toFirestore());

  @override
  Future<Result<void>> update(AppUser user) => updateDoc(
    path: _path,
    id: user.id,
    data: {
      ...user.toFirestore(),
      'updatedAt': FirestoreRepository.serverNow,
      // activeTaskCount is excluded deliberately: it is maintained only
      // by adjustActiveTaskCount's atomic increment. Letting a general
      // update write it would reintroduce the lost-update race that
      // method exists to prevent.
    }..remove('activeTaskCount'),
  );

  @override
  Future<Result<void>> createAccount({
    required AppUser user,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(_path).doc(user.id);
    if ((await transaction.get(reference)).exists) {
      throw FirestoreRepository.precondition(
        'An account profile already exists for this sign-in.',
      );
    }

    transaction.set(reference, {
      ...user.toFirestore(),
      'createdAt': FirestoreRepository.serverNow,
      'updatedAt': FirestoreRepository.serverNow,
    });

    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.created,
      entityType: _path,
      entityId: user.id,
      description: 'Created ${user.role.label} account for ${user.fullName}',
      changes: {'email': user.email, 'role': user.role.id},
    );
  });

  @override
  Future<Result<void>> updateAccount({
    required AppUser updated,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(_path).doc(updated.id);
    final snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound('No account ${updated.id}');
    }

    // The stored account, not the caller's copy: another administrator
    // may have changed it since the dialog opened.
    final current = AppUser.fromFirestore(snapshot);
    final roleChanges = updated.role != current.role;

    if (roleChanges && updated.id == actor.id) {
      throw FirestoreRepository.precondition(
        'You cannot change your own role. Ask another administrator.',
      );
    }
    if (roleChanges && current.activeTaskCount > 0) {
      final count = current.activeTaskCount;
      throw FirestoreRepository.precondition(
        '${current.fullName} still has $count active work '
        'order${count == 1 ? '' : 's'}. Finish or reassign them before '
        'changing their role.',
      );
    }

    // A trade and leave status mean something only for maintenance
    // personnel; anyone else carries neither.
    final isPersonnel = updated.role == UserRole.maintenancePersonnel;
    final next = <String, Object?>{
      'fullName': updated.fullName.trim(),
      'role': updated.role.id,
      'department': _blankToNull(updated.department),
      'contactNumber': _blankToNull(updated.contactNumber),
      'specialization': isPersonnel ? updated.specialization?.id : null,
      'availability': isPersonnel
          ? (updated.availability ?? PersonnelAvailability.available).id
          : null,
    };
    final previous = <String, Object?>{
      'fullName': current.fullName,
      'role': current.role.id,
      'department': current.department,
      'contactNumber': current.contactNumber,
      'specialization': current.specialization?.id,
      'availability': current.availability?.id,
    };

    final changed = {
      for (final key in next.keys)
        if (next[key] != previous[key])
          key: {'from': previous[key], 'to': next[key]},
    };
    if (changed.isEmpty) return;

    transaction.update(reference, {
      for (final key in changed.keys) key: next[key],
      'updatedAt': FirestoreRepository.serverNow,
    });

    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.updated,
      entityType: _path,
      entityId: updated.id,
      description: roleChanges
          ? 'Changed ${current.fullName} from ${current.role.label} to '
                '${updated.role.label}'
          : 'Updated account details for ${current.fullName}',
      changes: changed,
    );
  });

  @override
  Future<Result<void>> setAccountStatus(
    String uid,
    AccountStatus status, {
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(_path).doc(uid);
    final snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw FirestoreRepository.notFound('No account $uid');

    final current = AppUser.fromFirestore(snapshot);
    if (current.accountStatus == status) return;
    if (uid == actor.id && status != AccountStatus.active) {
      throw FirestoreRepository.precondition(
        'You cannot deactivate your own account. Ask another administrator.',
      );
    }

    transaction.update(reference, {
      'accountStatus': status.id,
      'updatedAt': FirestoreRepository.serverNow,
    });

    final activating = status == AccountStatus.active;
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.statusChanged,
      entityType: _path,
      entityId: uid,
      description:
          '${activating ? 'Reactivated' : 'Deactivated'} the account of '
          '${current.fullName}',
      changes: {'from': current.accountStatus.id, 'to': status.id},
    );
  });

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<Result<void>> setAvailability(
    String uid,
    PersonnelAvailability availability,
  ) => updateDoc(
    path: _path,
    id: uid,
    data: {
      'availability': availability.id,
      'updatedAt': FirestoreRepository.serverNow,
    },
  );

  @override
  Future<Result<void>> adjustActiveTaskCount(String uid, int delta) =>
      updateDoc(
        path: _path,
        id: uid,
        data: {
          // FieldValue.increment is applied server-side, so two tasks
          // assigned at the same moment each add 1 instead of both
          // reading the same value and writing the same result.
          'activeTaskCount': FieldValue.increment(delta),
          'updatedAt': FirestoreRepository.serverNow,
        },
      );

  @override
  Future<Result<void>> setFcmToken(String uid, String? token) => updateDoc(
    path: _path,
    id: uid,
    data: {'fcmToken': token, 'updatedAt': FirestoreRepository.serverNow},
  );
}
