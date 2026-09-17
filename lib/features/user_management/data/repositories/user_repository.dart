import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/utils/result.dart';
import '../models/app_user.dart';

/// Abstract contract for the `users` collection.
///
/// **Interface only** — the Firestore-calling implementation is Objective
/// 1.C's, once Firebase is configured. Callers depend on this, never on
/// `cloud_firestore` (Shared Backend Contract rule 1,
/// docs/architecture_decisions.md).
abstract interface class UserRepository {
  Future<Result<AppUser>> getById(String uid);

  /// Live view of one user, for reacting to role or status changes without
  /// a re-login.
  Stream<Result<AppUser>> watchById(String uid);

  /// All users, for the Admin user-management table (manuscript §1.5).
  Future<Result<List<AppUser>>> getAll({UserRole? role});

  /// Maintenance personnel filtered for assignment, backing the Admin
  /// personnel list (Figure 17). [specializationId] takes a
  /// `DamageCategory.id` so the caller can filter by trade.
  Future<Result<List<AppUser>>> getPersonnel({
    String? specializationId,
    PersonnelAvailability? availability,
  });

  Future<Result<void>> create(AppUser user);

  Future<Result<void>> update(AppUser user);

  /// Activate or deactivate an account (§1.5 "account activation or
  /// deactivation"). Separate from [update] because it is a distinct
  /// administrative act that must be audited.
  Future<Result<void>> setAccountStatus(String uid, AccountStatus status);

  Future<Result<void>> setAvailability(
    String uid,
    PersonnelAvailability availability,
  );

  /// Adjusts the denormalized `activeTaskCount` by [delta].
  ///
  /// Exists as its own method rather than going through [update] because
  /// it must be an atomic increment: two tasks assigned concurrently must
  /// not both read the same count and write the same result. The
  /// implementation is expected to use a Firestore atomic increment, not a
  /// read-modify-write.
  Future<Result<void>> adjustActiveTaskCount(String uid, int delta);

  /// Stores the device push token used by Cloud Messaging.
  Future<Result<void>> setFcmToken(String uid, String? token);
}
