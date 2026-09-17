/// Whether a user account may sign in. Backs the "account activation or
/// deactivation" capability listed under user-account management
/// (manuscript §1.5).
enum AccountStatus {
  active,
  inactive;

  bool get canSignIn => this == AccountStatus.active;

  /// The value persisted on `users/{uid}.accountStatus`.
  String get id => name;

  static AccountStatus fromId(String id) => AccountStatus.values.firstWhere(
    (status) => status.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown AccountStatus'),
  );
}
