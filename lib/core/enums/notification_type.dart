/// Category of push/in-app notification. Values come from the notification
/// triggers listed in manuscript §1.5: "report acknowledgment, work-order
/// and task assignment, status updates, and maintenance completion", plus
/// the separately listed "automatic low-stock alerts".
enum NotificationType {
  reportAcknowledged,
  workOrderAssigned,
  taskAssigned,
  statusUpdate,
  maintenanceCompleted,
  lowStockAlert;

  /// The value persisted on `notifications/{id}.type`.
  String get id => name;

  static NotificationType fromId(String id) =>
      NotificationType.values.firstWhere(
        (type) => type.id == id,
        orElse: () =>
            throw ArgumentError.value(id, 'id', 'Unknown NotificationType'),
      );
}
