import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/personnel_availability.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
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

  /// Live feed of every account, for the User Accounts table (Objective
  /// 2.C). Unfiltered and unsorted: the table filters by role tab and
  /// search in memory, and sorts by name, so one listener serves them all.
  Stream<Result<List<AppUser>>> watchAll();

  /// Maintenance personnel filtered for assignment, backing the Admin
  /// personnel list (Figure 17). [specializationId] takes a
  /// `DamageCategory.id` so the caller can filter by trade.
  Future<Result<List<AppUser>>> getPersonnel({
    String? specializationId,
    PersonnelAvailability? availability,
  });

  /// Live feed of every maintenance-personnel account, active or not, for
  /// the Task Assignment availability panel (Objective 2.B).
  ///
  /// A stream rather than [getPersonnel]'s one-shot read because
  /// `activeTaskCount` changes the moment an assignment commits; a panel
  /// showing yesterday's workload would steer the next assignment wrong.
  /// Filtering by trade happens client-side: the whole roster is small,
  /// and ranking the matching trade first beats hiding everyone else.
  Stream<Result<List<AppUser>>> watchPersonnel();

  Future<Result<void>> create(AppUser user);

  Future<Result<void>> update(AppUser user);

  /// Saves the profile of an account whose sign-in was just provisioned,
  /// together with its audit entry, in one transaction. Refuses if a
  /// profile already exists under that uid.
  Future<Result<void>> createAccount({
    required AppUser user,
    required AuditActor actor,
  });

  /// An administrator's edits: name, role, department, contact number,
  /// trade and leave (§1.5 "role and permission assignment"). Audited.
  ///
  /// Re-reads the stored account and refuses to change [actor]'s own role —
  /// the last administrator demoting themselves would lock everyone out —
  /// or the role of someone still holding work orders, which would strand
  /// that work. Email and account status are not edited here: email is the
  /// sign-in identity, and status has [setAccountStatus].
  Future<Result<void>> updateAccount({
    required AppUser updated,
    required AuditActor actor,
  });

  /// Activate or deactivate an account (§1.5 "account activation or
  /// deactivation"). Separate from [update] because it is a distinct
  /// administrative act that must be audited. Refuses [actor]'s own
  /// account, for the same reason [updateAccount] refuses their role.
  Future<Result<void>> setAccountStatus(
    String uid,
    AccountStatus status, {
    required AuditActor actor,
  });

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
