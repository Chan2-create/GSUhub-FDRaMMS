/// The three authorized user roles in GSUhub (manuscript Ch. I, §1.5 Scope
/// and Limitations). Each role is bound to exactly one client platform:
/// [requestor] and [maintenancePersonnel] are mobile-only, [admin] is
/// web-only. Students are never authorized under any role.
enum UserRole {
  /// DOrSU faculty or staff member who submits facility damage reports.
  requestor,

  /// GSU maintenance staff who execute assigned work orders.
  maintenancePersonnel,

  /// Authorized GSU Administrator who manages the web dashboard.
  admin;

  /// The value persisted on the `users/{uid}.role` Firestore field.
  String get id => name;

  /// Resolves a [UserRole] from its persisted Firestore [id].
  ///
  /// Throws an [ArgumentError] if [id] does not match a known role, since an
  /// unrecognized role on a user document indicates corrupted or tampered
  /// data rather than a recoverable state.
  static UserRole fromId(String id) => UserRole.values.firstWhere(
    (role) => role.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown UserRole'),
  );
}
