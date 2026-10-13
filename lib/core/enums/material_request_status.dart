/// Where a technician's request for more materials stands (Objective 6.B,
/// Figure Group 43's "Request History"). DERIVED: the design shows
/// "Pending" and an admin note; approved and declined are its outcomes.
enum MaterialRequestStatus {
  /// Waiting for GSU.
  pending,

  /// Granted: the items joined the work order's pre-assigned materials.
  approved,

  /// Refused, with the administrator's note saying why.
  declined;

  /// The value persisted on `material_requests/{id}.status`.
  String get id => name;

  /// As the request history prints it.
  String get label => switch (this) {
    MaterialRequestStatus.pending => 'Pending',
    MaterialRequestStatus.approved => 'Approved',
    MaterialRequestStatus.declined => 'Declined',
  };

  static MaterialRequestStatus fromId(String id) =>
      MaterialRequestStatus.values.firstWhere(
        (status) => status.id == id,
        orElse: () => throw ArgumentError.value(
          id,
          'id',
          'Unknown MaterialRequestStatus',
        ),
      );
}
