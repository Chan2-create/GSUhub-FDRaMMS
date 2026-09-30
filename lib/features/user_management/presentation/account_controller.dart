import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/damage_categories.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/di/service_providers.dart';
import '../../../core/enums/account_status.dart';
import '../../../core/enums/personnel_availability.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/account_provisioning_service.dart';
import '../../../core/utils/result.dart';
import '../../audit/data/models/audit_actor.dart';
import '../../audit/presentation/current_actor_provider.dart';
import '../data/models/app_user.dart';

/// The administrator's account actions (Objective 2.C; manuscript §1.5
/// "role and permission assignment and account activation or
/// deactivation").
///
/// Thin on purpose, like the 2.B controllers: the rules — no self-lockout,
/// no role change for someone holding work, every change audited — live in
/// the repository and the security rules, where a second caller cannot
/// skip them. This resolves who is acting and shapes the input.
class AccountController {
  const AccountController(this._ref);

  final Ref _ref;

  /// A new maintenance-personnel account: its sign-in, then its profile,
  /// then an email asking the person to set a password. Nobody chooses or
  /// sees the password.
  Future<Result<ProvisionedAccount>> createMaintenanceAccount({
    required String fullName,
    required String email,
    required DamageCategory specialization,
    String? department,
    String? contactNumber,
  }) async {
    final actor = await _actor();
    if (actor == null) return const Result.failure(_sessionExpired);

    return _ref
        .read(accountProvisioningServiceProvider)
        .provision(
          email: email.trim(),
          writeProfile: (uid) async {
            final now = DateTime.now().toUtc();
            final AppUser user;
            try {
              user = AppUser(
                id: uid,
                fullName: fullName.trim(),
                email: email.trim(),
                role: UserRole.maintenancePersonnel,
                accountStatus: AccountStatus.active,
                department: _blankToNull(department),
                contactNumber: _blankToNull(contactNumber),
                specialization: specialization,
                availability: PersonnelAvailability.available,
                createdAt: now,
                updatedAt: now,
              );
            } on ValidationException catch (error) {
              return Result.failure(ValidationFailure(error.message));
            }
            return _ref
                .read(userRepositoryProvider)
                .createAccount(user: user, actor: actor);
          },
        );
  }

  /// Saves an edit. The repository re-reads the stored account and refuses
  /// what would lock someone out or strand their work.
  Future<Result<void>> update(AppUser updated) async {
    final actor = await _actor();
    if (actor == null) return const Result.failure(_sessionExpired);
    return _ref
        .read(userRepositoryProvider)
        .updateAccount(updated: updated, actor: actor);
  }

  Future<Result<void>> setStatus(AppUser person, AccountStatus status) async {
    final actor = await _actor();
    if (actor == null) return const Result.failure(_sessionExpired);
    return _ref
        .read(userRepositoryProvider)
        .setAccountStatus(person.id, status, actor: actor);
  }

  /// Emails [person] a link to set a new password — for a forgotten one,
  /// or when the setup email from account creation did not arrive.
  Future<Result<void>> sendPasswordReset(AppUser person) => _ref
      .read(authServiceProvider)
      .sendPasswordResetEmail(email: person.email);

  Future<AuditActor?> _actor() => _ref.read(currentActorProvider.future);

  static const Failure _sessionExpired = PermissionFailure(
    'Your session has expired. Please sign in again.',
  );

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final accountControllerProvider = Provider(AccountController.new);
