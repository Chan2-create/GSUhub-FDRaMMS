import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/features/notifications/data/models/report_notice.dart';

/// Which moves a requestor is notified of, and what they are told
/// (Objective 3.B).
void main() {
  ReportNotice? notice(
    ReportStatus to, {
    ReportStatus? from,
    String? personnelName,
    String? reason,
    String? mergedInto,
  }) => ReportNotice.forMove(
    to: to,
    reportTitle: 'Leaking pipe',
    from: from,
    personnelName: personnelName,
    reason: reason,
    mergedInto: mergedInto,
  );

  test('the seven events of §1.5 notify; the rest stay on the timeline', () {
    final notified = {
      for (final status in ReportStatus.values)
        if (notice(status) != null) status,
    };
    expect(notified, {
      ReportStatus.submitted,
      ReportStatus.approved,
      ReportStatus.assigned,
      ReportStatus.inProgress,
      ReportStatus.completed,
      ReportStatus.rejected,
      ReportStatus.merged,
    });
  });

  test('each event has its notification type', () {
    expect(
      notice(ReportStatus.submitted)!.type,
      NotificationType.reportAcknowledged,
    );
    expect(
      notice(ReportStatus.assigned)!.type,
      NotificationType.workOrderAssigned,
    );
    expect(
      notice(ReportStatus.completed)!.type,
      NotificationType.maintenanceCompleted,
    );
    for (final status in [
      ReportStatus.approved,
      ReportStatus.inProgress,
      ReportStatus.rejected,
      ReportStatus.merged,
    ]) {
      expect(notice(status)!.type, NotificationType.statusUpdate);
    }
  });

  test('names the report, the person, the reason and the parent', () {
    expect(notice(ReportStatus.approved)!.body, contains('"Leaking pipe"'));
    expect(
      notice(ReportStatus.assigned, personnelName: 'Juan Luna')!.body,
      startsWith('Juan Luna was assigned'),
    );
    expect(
      notice(ReportStatus.rejected, reason: 'Outside GSU scope.')!.body,
      endsWith('not accepted: Outside GSU scope.'),
    );
    expect(
      notice(ReportStatus.merged, mergedInto: 'rep-0001')!.body,
      contains('#REP-0001'),
    );
  });

  test('a send-back is told as work resumed', () {
    expect(
      notice(ReportStatus.inProgress, from: ReportStatus.forReview)!.title,
      'Work resumed',
    );
    expect(
      notice(ReportStatus.inProgress, from: ReportStatus.assigned)!.title,
      'Work started',
    );
  });

  test('a long reason is clipped to fit the notification', () {
    final reason = 'x' * 600;
    final body = notice(ReportStatus.rejected, reason: reason)!.body;
    expect(body.length, lessThan(400));
    expect(body, endsWith('…'));
  });

  test('a completed report asks for a rating', () {
    expect(notice(ReportStatus.completed)!.body, contains('rate the service'));
  });
}
