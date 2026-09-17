/// Work-order tracking status, matching the four Kanban columns shown in
/// the Admin "Work Order Management" board (manuscript Figure 19):
/// Pending -> In Progress -> For Review -> Completed.
enum WorkOrderStatus {
  /// Created and awaiting personnel to begin work.
  pending,

  /// Actively being worked on by assigned maintenance personnel.
  inProgress,

  /// Work performed; awaiting Administrator review before closure.
  forReview,

  /// Reviewed and finished.
  completed;

  static const Map<WorkOrderStatus, Set<WorkOrderStatus>> _allowedTransitions =
      <WorkOrderStatus, Set<WorkOrderStatus>>{
        WorkOrderStatus.pending: {WorkOrderStatus.inProgress},
        WorkOrderStatus.inProgress: {WorkOrderStatus.forReview},
        // Rework loop: an Administrator may bounce a work order back to
        // in-progress if the submitted accomplishment report is incomplete.
        // Not explicit in the source manuscript; documented as an assumption
        // in docs/architecture_decisions.md.
        WorkOrderStatus.forReview: {
          WorkOrderStatus.completed,
          WorkOrderStatus.inProgress,
        },
        WorkOrderStatus.completed: <WorkOrderStatus>{},
      };

  /// Whether a work order currently in this status may transition to
  /// [next].
  bool canTransitionTo(WorkOrderStatus next) =>
      _allowedTransitions[this]?.contains(next) ?? false;

  /// Terminal statuses have no further allowed transitions.
  bool get isTerminal => _allowedTransitions[this]?.isEmpty ?? true;

  /// The value persisted on the `work_orders/{id}.status` field.
  String get id => name;

  static WorkOrderStatus fromId(String id) => WorkOrderStatus.values.firstWhere(
    (status) => status.id == id,
    orElse: () =>
        throw ArgumentError.value(id, 'id', 'Unknown WorkOrderStatus'),
  );
}
