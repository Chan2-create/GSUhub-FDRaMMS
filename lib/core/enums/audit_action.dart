/// Kind of state change recorded in the append-only `audit_logs`
/// collection.
///
/// The manuscript requires auditability — "The system shall record major
/// user activities such as report submissions, task assignments, status
/// updates, and work order completion for monitoring and accountability
/// purposes" (§3.4, Non-Functional Requirements: Auditability) — but never
/// enumerates the action vocabulary. This closed set is DERIVED from the
/// activities that section names plus duplicate merging (§3.4). Flagged in
/// docs/data_dictionary.md.
enum AuditAction {
  created,
  updated,
  statusChanged,
  assigned,
  merged,
  deleted;

  /// The value persisted on `audit_logs/{id}.action`.
  String get id => name;

  static AuditAction fromId(String id) => AuditAction.values.firstWhere(
    (action) => action.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown AuditAction'),
  );
}
