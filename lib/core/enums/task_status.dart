/// Completion state of an individual task within a work order, backing the
/// personnel daily task list (manuscript Figure 24: unchecked items,
/// "Upload Proof", and a struck-through "PROOF SUBMITTED" item).
///
/// Deliberately coarser than [WorkOrderStatus]: a task is a checklist item
/// a technician ticks off, not something an Administrator reviews. The
/// work order it belongs to carries the reviewable lifecycle.
enum TaskStatus {
  pending,
  inProgress,
  completed;

  /// The value persisted on `tasks/{id}.status`.
  String get id => name;

  static TaskStatus fromId(String id) => TaskStatus.values.firstWhere(
    (status) => status.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown TaskStatus'),
  );
}
