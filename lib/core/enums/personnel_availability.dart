/// Work availability of a maintenance personnel account, shown to the
/// Administrator when assigning work orders (manuscript Figure 17,
/// "Maintenance Personnel": AVAILABLE NOW / ON TASK / ON LEAVE, with a
/// per-row status of Available or Busy).
///
/// Distinct from [AccountStatus]: an account can be `active` (may sign in)
/// while the person is `onLeave` (should not be assigned work).
enum PersonnelAvailability {
  available,
  busy,
  onLeave;

  /// Whether the Administrator should be offered this person when
  /// assigning a work order.
  bool get isAssignable => this == PersonnelAvailability.available;

  /// The value persisted on `users/{uid}.availability`.
  String get id => name;

  static PersonnelAvailability fromId(String id) =>
      PersonnelAvailability.values.firstWhere(
        (availability) => availability.id == id,
        orElse: () => throw ArgumentError.value(
          id,
          'id',
          'Unknown PersonnelAvailability',
        ),
      );
}
