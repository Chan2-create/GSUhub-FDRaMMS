/// Whether a user account may sign in. Backs the "account activation or
/// deactivation" capability listed under user-account management
/// (manuscript §1.5).
enum AccountStatus {
  active,
  inactive,

  /// Signed themselves up from the faculty and staff app and waiting for an
  /// administrator to approve them (Objective 3.A). Kept apart from
  /// [inactive] so a new request is not mistaken for someone who left, and
  /// so the person is told they are waiting rather than deactivated.
  pending;

  bool get canSignIn => this == AccountStatus.active;

  /// The value persisted on `users/{uid}.accountStatus`.
  String get id => name;

  /// As the User Accounts table writes it.
  String get label => switch (this) {
    AccountStatus.active => 'ACTIVE',
    AccountStatus.inactive => 'INACTIVE',
    AccountStatus.pending => 'PENDING',
  };

  static AccountStatus fromId(String id) => AccountStatus.values.firstWhere(
    (status) => status.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown AccountStatus'),
  );
}
