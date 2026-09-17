/// Lifecycle status of a facility damage report, spanning submission
/// through closure (manuscript §1.2, §1.7 "Maintenance Request Lifecycle";
/// §3.4 duplicate-report and rule-based classification rules).
///
/// The forward path is:
/// `submitted -> underReview -> approved -> assigned -> inProgress ->
/// forReview -> completed -> closed`.
///
/// From [underReview], a report may branch to [merged], [rejected], or
/// [archived] per the duplicate-report handling rules in §3.4. From
/// [forReview], a report may be sent back to [inProgress] for rework; the
/// source documents describe review and completion narratively but do not
/// specify whether rework is allowed, so this transition is a reasonable
/// addition documented in docs/architecture_decisions.md pending
/// confirmation.
enum ReportStatus {
  /// Newly created by a requestor; not yet reviewed.
  submitted,

  /// Under GSU Administrator review for classification and duplicate
  /// detection.
  underReview,

  /// Reviewed and confirmed as a legitimate, non-duplicate concern.
  approved,

  /// A work order has been created and assigned to personnel.
  assigned,

  /// Maintenance personnel are actively working the assigned work order.
  inProgress,

  /// Work has been performed and is awaiting Administrator sign-off.
  forReview,

  /// Sign-off given; maintenance work is finished.
  completed,

  /// Terminal: fully closed after completion (and any post-service
  /// feedback has been collected).
  closed,

  /// Terminal: consolidated into another report as a duplicate.
  merged,

  /// Terminal: dismissed as invalid, unrelated, or out of GSU scope.
  rejected,

  /// Terminal: withdrawn from active tracking without being resolved.
  archived;

  static const Map<ReportStatus, Set<ReportStatus>> _allowedTransitions =
      <ReportStatus, Set<ReportStatus>>{
        ReportStatus.submitted: {ReportStatus.underReview},
        ReportStatus.underReview: {
          ReportStatus.approved,
          ReportStatus.merged,
          ReportStatus.rejected,
          ReportStatus.archived,
        },
        ReportStatus.approved: {ReportStatus.assigned},
        ReportStatus.assigned: {ReportStatus.inProgress},
        ReportStatus.inProgress: {ReportStatus.forReview},
        ReportStatus.forReview: {
          ReportStatus.completed,
          ReportStatus.inProgress,
        },
        ReportStatus.completed: {ReportStatus.closed},
        ReportStatus.closed: <ReportStatus>{},
        ReportStatus.merged: <ReportStatus>{},
        ReportStatus.rejected: <ReportStatus>{},
        ReportStatus.archived: <ReportStatus>{},
      };

  /// Whether a report currently in this status may transition to [next].
  bool canTransitionTo(ReportStatus next) =>
      _allowedTransitions[this]?.contains(next) ?? false;

  /// Terminal statuses have no further allowed transitions.
  bool get isTerminal => _allowedTransitions[this]?.isEmpty ?? true;

  /// The value persisted on the `damage_reports/{id}.status` field.
  String get id => name;

  static ReportStatus fromId(String id) => ReportStatus.values.firstWhere(
    (status) => status.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown ReportStatus'),
  );
}
