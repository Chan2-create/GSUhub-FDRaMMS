import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/utils/result.dart';
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
  Future<Result<void>> setAccountStatus(String uid, AccountStatus status) =>
      updateDoc(
        path: _path,
        id: uid,
        data: {
          'accountStatus': status.id,
          'updatedAt': FirestoreRepository.serverNow,
        },
      );

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
