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
  accountRequested,

  // Tool requests (2026-11-16; supabase/migrations/*_tool_requests.sql).

  /// To the technician: GSU checked a tool out to them, to collect and
  /// confirm by scanning it.
  toolCheckoutRequested,

  /// To the technician: GSU asks for a tool back by a date and time.
  toolReturnRequested,

  /// To the technician: a requested return is due within the hour.
  toolReturnDue,

  /// To the administrators: a technician confirmed collecting a tool.
  toolCheckoutConfirmed,

  /// To the administrators: a technician confirmed returning a tool.
  toolReturned,

  /// To the administrators: a checkout is still not collected an hour
  /// past its time.
  toolCheckoutPending,

  /// To both: a requested return is past its time.
  toolOverdue,

  /// To both: a request was cancelled, or lapsed uncollected.
  toolRequestCancelled;

  /// Whether this is about a tool request.
  bool get isAboutTools => switch (this) {
    toolCheckoutRequested ||
    toolReturnRequested ||
    toolReturnDue ||
    toolCheckoutConfirmed ||
    toolReturned ||
    toolCheckoutPending ||
    toolOverdue ||
    toolRequestCancelled => true,
    _ => false,
  };

  /// The value persisted on `notifications/{id}.type`.
  String get id => name;

  static NotificationType fromId(String id) =>
      NotificationType.values.firstWhere(
        (type) => type.id == id,
        orElse: () =>
            throw ArgumentError.value(id, 'id', 'Unknown NotificationType'),
      );
}
