import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/reporting/data/models/report_submission.dart';

import '../../support/fake_firestore_repositories.dart';

/// The requestor's notifications (Objective 3.B), written by the real
/// repositories in the same transaction as each move they announce.
void main() {
  late FirestoreHarness h;
  const admin = FirestoreHarness.admin;

  setUp(() => h = FirestoreHarness());

  /// The one notification written so far.
  Future<Map<String, dynamic>> onlyNotice() async {
    final all = await h.notifications();
    expect(all, hasLength(1));
    return all.single;
  }

  test('filing a report tells the requestor it was received', () async {
    final id = h.reports.newReportId();
    await h.reports.submit(
      reportId: id,
      submission: const ReportSubmission(
        reporter: AuditActor(id: 'faculty-1', name: 'Maria Santos'),
        title: 'Cracked window pane',
        description: 'The pane beside the door is cracked across.',
        requestorPriority: PriorityLevel.high,
        facilityId: 'fac-engineering',
        facilityName: 'Engineering Building',
      ),
    );

    final notice = await onlyNotice();
    expect(notice['recipientId'], 'faculty-1');
    expect(notice['type'], 'reportAcknowledged');
    expect(notice['title'], 'Report received');
    expect(notice['body'], contains('"Cracked window pane"'));
    expect(notice['relatedEntityType'], FirestorePaths.damageReports);
    expect(notice['relatedEntityId'], id);
    expect(notice['isRead'], isFalse);
    expect(isTimestamp(notice['createdAt']), isTrue);
  });

  test(
    'starting a review tells nobody; approving tells the reporter',
    () async {
      await h.addReport('r1', status: ReportStatus.submitted);

      await h.reports.transitionStatus(
        reportId: 'r1',
        to: ReportStatus.underReview,
        actor: admin,
      );
      expect(await h.notifications(), isEmpty);

      await h.reports.transitionStatus(
        reportId: 'r1',
        to: ReportStatus.approved,
        actor: admin,
      );
      final notice = await onlyNotice();
      expect(notice['recipientId'], 'faculty-1');
      expect(notice['type'], 'statusUpdate');
      expect(notice['title'], 'Report approved');
    },
  );

  test('a rejection gives the reason', () async {
    await h.addReport('r1', status: ReportStatus.underReview);

    await h.reports.transitionStatus(
      reportId: 'r1',
      to: ReportStatus.rejected,
      actor: admin,
      reason: 'Outside GSU scope.',
    );

    final notice = await onlyNotice();
    expect(notice['title'], 'Report not accepted');
    expect(notice['body'], endsWith('Outside GSU scope.'));
  });

  test('a refused move tells nobody', () async {
    await h.addReport('r1', status: ReportStatus.submitted);

    await h.reports.transitionStatus(
      reportId: 'r1',
      to: ReportStatus.approved,
      actor: admin,
    );

    expect(await h.notifications(), isEmpty);
  });

  test('assignment names who will do the work', () async {
    await h.addReport('r1');
    await h.addPersonnel('p1');

    await h.workOrders.assignFromReport(
      reportId: 'r1',
      personnelId: 'p1',
      actor: admin,
    );

    final notice = await onlyNotice();
    expect(notice['type'], 'workOrderAssigned');
    expect(notice['body'], startsWith('Marcus Wright was assigned'));
  });

  test('work starting and finishing are told; sign-off is not', () async {
    await h.addReport('r1', status: ReportStatus.assigned, workOrderId: 'w1');
    await h.addWorkOrder(
      'w1',
      reportIds: ['r1'],
      status: WorkOrderStatus.pending,
    );

    await h.workOrders.setStatus(
      'w1',
      WorkOrderStatus.inProgress,
      actor: admin,
    );
    expect((await onlyNotice())['title'], 'Work started');

    await h.workOrders.setStatus('w1', WorkOrderStatus.forReview, actor: admin);
    expect(await h.notifications(), hasLength(1));

    await h.workOrders.setStatus('w1', WorkOrderStatus.completed, actor: admin);
    final titles = [for (final n in await h.notifications()) n['title']];
    expect(titles, containsAll(['Work started', 'Work completed']));
    final completed = (await h.notifications()).firstWhere(
      (n) => n['title'] == 'Work completed',
    );
    expect(completed['type'], 'maintenanceCompleted');
    expect(completed['body'], contains('rate the service'));
  });

  test('work sent back from sign-off is told as resumed', () async {
    await h.addReport('r1', status: ReportStatus.forReview, workOrderId: 'w1');
    await h.addWorkOrder(
      'w1',
      reportIds: ['r1'],
      status: WorkOrderStatus.forReview,
    );

    await h.workOrders.setStatus(
      'w1',
      WorkOrderStatus.inProgress,
      actor: admin,
    );

    expect((await onlyNotice())['title'], 'Work resumed');
  });

  test('a move that aborts tells nobody', () async {
    await h.addReport('r1', status: ReportStatus.rejected, workOrderId: 'w1');
    await h.addWorkOrder(
      'w1',
      reportIds: ['r1'],
      status: WorkOrderStatus.pending,
    );

    await h.workOrders.setStatus(
      'w1',
      WorkOrderStatus.inProgress,
      actor: admin,
    );

    expect(await h.notifications(), isEmpty);
  });

  test('merging tells each duplicate’s reporter where it went', () async {
    await h.addReport('parent');
    await h.addReport('d1', status: ReportStatus.underReview);
    await h.addReport(
      'd2',
      status: ReportStatus.underReview,
      reporterId: 'faculty-2',
    );

    await h.reports.mergeDuplicates(
      parentReportId: 'parent',
      duplicateReportIds: ['d1', 'd2'],
      mergedBy: admin.id,
    );

    final notices = await h.notifications();
    expect(
      {for (final n in notices) n['recipientId']},
      {'faculty-1', 'faculty-2'},
    );
    expect(notices.every((n) => n['title'] == 'Report merged'), isTrue);
    expect(notices.first['body'], contains('#DR-PARENT'));
  });

  test('merging a report that does not exist writes nothing', () async {
    await h.addReport('parent');

    final result = await h.reports.mergeDuplicates(
      parentReportId: 'parent',
      duplicateReportIds: ['missing'],
      mergedBy: admin.id,
    );

    expect(result.isSuccess, isFalse);
    expect(await h.notifications(), isEmpty);
    expect(await h.history('missing'), isEmpty);
  });
}
