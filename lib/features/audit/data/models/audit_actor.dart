/// Who performed an audited action.
///
/// Repositories that change lifecycle state take one of these and write
/// the audit entry in the same transaction as the change itself — so a
/// status can never move without a record of who moved it, and a record
/// can never exist for a move that failed.
class AuditActor {
  const AuditActor({required this.id, required this.name});

  /// The signed-in user's uid. Security rules require it to match the
  /// requester (`audit_logs` create rule).
  final String id;

  /// Display name at the time of the action, denormalized so the trail
  /// stays readable if the account is later renamed.
  final String name;
}
