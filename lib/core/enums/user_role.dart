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

  /// Display name, as the User Accounts screen writes it (Figma `89:4626`)
  /// — its role chip in capitals, its legend as-is. The single source:
  /// screens read this rather than keeping their own map.
  String get label => switch (this) {
    UserRole.requestor => 'End User',
    UserRole.maintenancePersonnel => 'Maintenance',
    UserRole.admin => 'Administrator',
  };

  /// How a person's own role is named to them, on their profile: the
  /// manuscript's words for the three kinds of user (§1.5).
  String get profileLabel => switch (this) {
    UserRole.requestor => 'Faculty / Staff',
    UserRole.maintenancePersonnel => 'Maintenance Personnel',
    UserRole.admin => 'GSU Administrator',
  };

  /// The User Accounts tab that lists this role.
  String get tabLabel => switch (this) {
    UserRole.requestor => 'End Users',
    UserRole.maintenancePersonnel => 'Maintenance Personnel',
    UserRole.admin => 'Administrators',
  };

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
