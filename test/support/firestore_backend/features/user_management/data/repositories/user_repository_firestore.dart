import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/table_names.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/personnel_availability.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/user_management/data/repositories/user_repository.dart';

import '../../../../core/data/firestore_records.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../audit/data/repositories/audit_writes.dart';

/// Firestore-backed [UserRepository]. Persistence only.
/// Objective 1 moved this data to Supabase; the app uses [UserRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreUserRepository extends FirestoreRepository
    implements UserRepository {
  const FirestoreUserRepository({required super.db, required super.guard});

  static const String _path = TableNames.users;

  @override
  Future<Result<AppUser>> getById(String uid) =>
      getOne(path: _path, id: uid, convert: fromDoc(AppUser.fromRecord));

  @override
  Stream<Result<AppUser>> watchById(String uid) =>
      watchOne(path: _path, id: uid, convert: fromDoc(AppUser.fromRecord));

  @override
  Future<Result<List<AppUser>>> getAll({UserRole? role}) {
    Query<Map<String, dynamic>> query = collection(_path);
    if (role != null) {
      query = query.where('role', isEqualTo: role.id);
    }
    return getMany(query: query, convert: fromDoc(AppUser.fromRecord));
  }

  @override
  Stream<Result<List<AppUser>>> watchAll() =>
      watchMany(query: collection(_path), convert: fromDoc(AppUser.fromRecord));

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

    return getMany(query: query, convert: fromDoc(AppUser.fromRecord));
  }

  @override
  Stream<Result<List<AppUser>>> watchPersonnel() => watchMany(
    // A single equality filter needs no composite index. Sorting by name
    // server-side would, so the caller orders the (small) roster instead.
    query: collection(_path)
        .where('role', isEqualTo: UserRole.maintenancePersonnel.id),
    convert: fromDoc(AppUser.fromRecord),
  );

  @override
  Future<Result<void>> create(AppUser user) =>
      setDoc(path: _path, id: user.id, data: user.toFields().forFirestore);

  @override
  Future<Result<void>> update(AppUser user) => updateDoc(
    path: _path,
    id: user.id,
    data: {
      ...user.toFields().forFirestore,
      'updatedAt': FirestoreRepository.serverNow,
      // activeTaskCount is excluded deliberately: it is maintained only
      // by adjustActiveTaskCount's atomic increment. Letting a general
      // update write it would reintroduce the lost-update race that
      // method exists to prevent.
    }..remove('activeTaskCount'),
  );

  @override
  Future<Result<void>> createSelfRegistration(AppUser user) => setDoc(
    path: _path,
    id: user.id,
    data: {
      ...user.toFields().forFirestore,
      // The rules check both against request time, so a device with a
      // wrong clock cannot back-date the request.
      'createdAt': FirestoreRepository.serverNow,
      'updatedAt': FirestoreRepository.serverNow,
    },
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
      ...user.toFields().forFirestore,
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
    final current = fromDoc(AppUser.fromRecord)(snapshot);
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

    final current = fromDoc(AppUser.fromRecord)(snapshot);
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
    final request = current.accountStatus == AccountStatus.pending;
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.statusChanged,
      entityType: _path,
      entityId: uid,
      description: switch ((request, activating)) {
        (true, true) => 'Approved the account request of ${current.fullName}',
        (true, false) => 'Declined the account request of ${current.fullName}',
        (false, true) => 'Reactivated the account of ${current.fullName}',
        (false, false) => 'Deactivated the account of ${current.fullName}',
      },
      changes: {'from': current.accountStatus.id, 'to': status.id},
    );
  });

  /// As delete_account: never one's own, never one with open work, and
  /// never one any record names (here: reports, work orders, tasks, loans
  /// and accomplishment reports).
  @override
  Future<Result<void>> deleteAccount(
    String uid, {
    required AuditActor actor,
  }) async {
    if (uid == actor.id) {
      return const Result.failure(
        ValidationFailure(
          'You cannot delete your own account. Ask another administrator.',
        ),
      );
    }
    final found = await getById(uid);
    final AppUser person;
    switch (found) {
      case Success(:final value):
        person = value;
      case Error(:final failure):
        return Result.failure(failure);
    }
    final raw = db.raw;
    final references = await guard.call(() async {
      final work = await raw
          .collection(TableNames.workOrders)
          .where('assignedPersonnelIds', arrayContains: uid)
          .get();
      final open = work.docs
          .where((doc) => doc.data()['status'] != WorkOrderStatus.completed.id)
          .length;
      var records = work.size;
      for (final (path, field) in [
        (TableNames.damageReports, 'reporterId'),
        (TableNames.tasks, 'assignedTo'),
        (TableNames.toolLoans, 'borrowedBy'),
        (TableNames.accomplishmentReports, 'submittedBy'),
      ]) {
        records +=
            (await raw
                    .collection(path)
                    .where(field, isEqualTo: uid)
                    .limit(1)
                    .get())
                .size;
      }
      return (open: open, records: records);
    });
    switch (references) {
      case Error(:final failure):
        return Result.failure(failure);
      case Success(value: (open: final open, records: _)) when open > 0:
        return Result.failure(
          ValidationFailure(
            '${person.fullName} is assigned to $open open work order'
            '${open == 1 ? '' : 's'}. Reassign ${open == 1 ? 'it' : 'them'} '
            'first.',
          ),
        );
      case Success(value: (open: _, records: final records)) when records > 0:
        return Result.failure(
          ValidationFailure(
            '${person.fullName} has records in GSUhub (reports, work or '
            'history), so the account stays to keep them. Deactivate it '
            'instead.',
          ),
        );
      case Success():
        break;
    }

    final notices = await guard.call(
      () => raw
          .collection(TableNames.notifications)
          .where('recipientId', isEqualTo: uid)
          .get(),
    );
    return db.runTransaction<void>((transaction) async {
      final docs = notices.fold(
        (snapshot) => snapshot.docs,
        (_) => const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
      for (final notice in docs) {
        transaction.delete(notice.reference);
      }
      transaction.delete(collection(_path).doc(uid));
      stageAuditEntry(
        transaction,
        raw,
        actor: actor,
        action: AuditAction.deleted,
        entityType: _path,
        entityId: uid,
        description:
            'Deleted the account of ${person.fullName} (${person.email})',
      );
    });
  }

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
