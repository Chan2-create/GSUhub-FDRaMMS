import '../../../../core/enums/notification_type.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/display_id.dart';

/// What a requestor is told when their report moves (Objective 3.B): the
/// notification's type, title and body.
///
/// Manuscript §1.5 names the events — "report acknowledgment, work-order
/// and task assignment, status updates, and maintenance completion" — and
/// 3.B settled which moves they are: received, approved, assigned, work
/// started, completed, rejected and merged. Review, sign-off, closing and
/// archiving appear on the timeline only. The wording is DERIVED; the
/// sources give none.
///
/// Free of Flutter imports on purpose: tool/seed_emulator.dart runs on
/// plain Dart and seeds its notifications with this same wording.
class ReportNotice {
  const ReportNotice({
    required this.type,
    required this.title,
    required this.body,
  });

  final NotificationType type;
  final String title;
  final String body;

  /// The longest stretch of an administrator's reason a notice quotes.
  /// The full reason is on the report itself.
  static const int reasonLimit = 280;

  /// The notice for a report titled [reportTitle] moving to [to], or null
  /// when the requestor is not notified of that move.
  ///
  /// [from] tells work resumed after a send-back from work started;
  /// [personnelName] names who was assigned; [reason] is a rejection's;
  /// [mergedInto] is the report a duplicate was folded into.
  static ReportNotice? forMove({
    required ReportStatus to,
    required String reportTitle,
    ReportStatus? from,
    String? personnelName,
    String? reason,
    String? mergedInto,
  }) {
    final report = '"$reportTitle"';
    return switch (to) {
      ReportStatus.submitted => ReportNotice(
        type: NotificationType.reportAcknowledged,
        title: 'Report received',
        body:
            'The General Services Unit received your report $report. You '
            'will be notified as it moves along.',
      ),
      ReportStatus.approved => ReportNotice(
        type: NotificationType.statusUpdate,
        title: 'Report approved',
        body:
            'Your report $report was approved and will be assigned to '
            'maintenance personnel.',
      ),
      ReportStatus.assigned => ReportNotice(
        type: NotificationType.workOrderAssigned,
        title: 'Personnel assigned',
        body: personnelName == null
            ? 'Maintenance personnel were assigned to your report $report.'
            : '$personnelName was assigned to your report $report.',
      ),
      ReportStatus.inProgress when from == ReportStatus.forReview =>
        ReportNotice(
          type: NotificationType.statusUpdate,
          title: 'Work resumed',
          body: 'Work on your report $report has resumed.',
        ),
      ReportStatus.inProgress => ReportNotice(
        type: NotificationType.statusUpdate,
        title: 'Work started',
        body: 'Work has started on your report $report.',
      ),
      ReportStatus.completed => ReportNotice(
        type: NotificationType.maintenanceCompleted,
        title: 'Work completed',
        body:
            'The work on your report $report is complete. Open it to rate '
            'the service.',
      ),
      ReportStatus.rejected => ReportNotice(
        type: NotificationType.statusUpdate,
        title: 'Report not accepted',
        body: reason == null || reason.trim().isEmpty
            ? 'Your report $report was not accepted.'
            : 'Your report $report was not accepted: ${_clip(reason.trim())}',
      ),
      ReportStatus.merged => ReportNotice(
        type: NotificationType.statusUpdate,
        title: 'Report merged',
        body: mergedInto == null
            ? 'Your report $report was merged with an earlier report of the '
                  'same damage.'
            : 'Your report $report was merged with report '
                  '${DisplayId.report(mergedInto)}, which reported the same '
                  'damage.',
      ),
      ReportStatus.underReview ||
      ReportStatus.forReview ||
      ReportStatus.closed ||
      ReportStatus.archived => null,
    };
  }

  static String _clip(String text) => text.length <= reasonLimit
      ? text
      : '${text.substring(0, reasonLimit).trimRight()}…';
}
