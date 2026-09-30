import '../utils/result.dart';

/// What provisioning produced.
class ProvisionedAccount {
  const ProvisionedAccount({required this.uid, required this.setupEmailSent});

  final String uid;

  /// Whether the "set your password" email went out. The account exists
  /// either way; when this is false the administrator can resend it from
  /// the account's row menu.
  final bool setupEmailSent;
}

/// Creates sign-in accounts on an administrator's behalf.
///
/// Separate from [AuthService] because it acts on *other* people's
/// accounts, never the signed-in one — and because the project is on the
/// Spark plan, which has no Cloud Functions to do this server-side.
///
/// Nobody is handed a password. The account is created with a random one
/// that is never shown or stored, and the person is emailed a link to set
/// their own.
abstract interface class AccountProvisioningService {
  /// Creates a sign-in account for [email], then runs [writeProfile] with
  /// its uid to save the matching `users` document.
  ///
  /// The two succeed or fail together: if [writeProfile] fails, the
  /// sign-in account is deleted again, so no login is left behind without
  /// a profile — which the route guard would read as "no access" and the
  /// administrator could not see to fix.
  Future<Result<ProvisionedAccount>> provision({
    required String email,
    required Future<Result<void>> Function(String uid) writeProfile,
  });
}
