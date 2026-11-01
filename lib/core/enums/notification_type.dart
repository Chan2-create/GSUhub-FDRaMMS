/// Category of push/in-app notification. Values come from the notification
/// triggers listed in manuscript §1.5: "report acknowledgment, work-order
/// and task assignment, status updates, and maintenance completion", plus
/// the separately listed "automatic low-stock alerts". The rest are the
/// administrator's own (Objective 7.A).
enum NotificationType {
  reportAcknowledged,
  workOrderAssigned,
  taskAssigned,
  statusUpdate,
  maintenanceCompleted,
  lowStockAlert,

  // An administrator's, for the console's notification centre (Objective
  // 7.A; supabase/migrations/*_admin_notifications.sql). DERIVED: each is a
  // moment §3.4 has the administrator act on.

  /// A report was filed.
  reportSubmitted,

  /// Work began on a work order.
  workStarted,

  /// An accomplishment report waits for sign-off.
  reviewRequested,

  /// A technician asked for materials.
  materialsRequested,

  /// Someone signed up and waits for approval.
  accountRequested;

  /// The value persisted on `notifications/{id}.type`.
  String get id => name;

  static NotificationType fromId(String id) =>
      NotificationType.values.firstWhere(
        (type) => type.id == id,
        orElse: () =>
            throw ArgumentError.value(id, 'id', 'Unknown NotificationType'),
      );
}
