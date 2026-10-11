import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/reporting/data/models/report_submission.dart';
import 'package:gsuhub/features/reporting/data/models/status_change.dart';

import '../../support/fake_firestore_repositories.dart';

/// The status history behind the requestor's timeline (Objective 3.B):
/// every move a repository makes writes one entry in the same transaction,
/// and a refused move writes none.
void main() {
  late FirestoreHarness h;
  const admin = FirestoreHarness.admin;

  setUp(() => h = FirestoreHarness());

  List<String> statusesOf(List<Map<String, dynamic>> entries) => [
    for (final entry in entries) entry['status'] as String,
  ];

  test('filing a report starts its history as submitted', () async {
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

    final history = await h.history(id);
    expect(statusesOf(history), ['submitted']);
    expect(history.single['changedBy'], 'faculty-1');
    expect(isTimestamp(history.single['changedAt']), isTrue);
  });

  test('a review decision is recorded, with the rejection reason', () async {
    await h.addReport('r1', status: ReportStatus.submitted);
    await h.reports.transitionStatus(
      reportId: 'r1',
      to: ReportStatus.underReview,
      actor: admin,
    );
    await h.reports.transitionStatus(
      reportId: 'r1',
      to: ReportStatus.rejected,
      actor: admin,
      reason: '  Outside GSU scope  ',
    );

    final history = await h.history('r1');
    expect(statusesOf(history), containsAll(['underReview', 'rejected']));
    final rejected = history.firstWhere((e) => e['status'] == 'rejected');
    expect(rejected['note'], 'Outside GSU scope');
    expect(rejected['changedBy'], admin.id);
  });

  test('a refused move writes no entry', () async {
    await h.addReport('r1', status: ReportStatus.submitted);

    await h.reports.transitionStatus(
      reportId: 'r1',
      to: ReportStatus.approved,
      actor: admin,
    );

    expect(await h.history('r1'), isEmpty);
  });

  test('assignment names who will do the work', () async {
    await h.addReport('r1');
    await h.addPersonnel('p1');

    await h.workOrders.assignFromReport(
      reportId: 'r1',
      personnelId: 'p1',
      actor: admin,
    );

    final history = await h.history('r1');
    expect(statusesOf(history), ['assigned']);
    expect(history.single['personnelName'], 'Marcus Wright');
    expect(history.single['personnelSpecialization'], 'electrical');
  });

  test("a work order's move is recorded on each report it carries", () async {
    await h.addReport('r1', status: ReportStatus.assigned, workOrderId: 'w1');
    await h.addReport('r2', status: ReportStatus.assigned, workOrderId: 'w1');
    await h.addWorkOrder(
      'w1',
      reportIds: ['r1', 'r2'],
      status: WorkOrderStatus.pending,
    );

    await h.workOrders.setStatus(
      'w1',
      WorkOrderStatus.inProgress,
      actor: admin,
    );

    expect(statusesOf(await h.history('r1')), ['inProgress']);
    expect(statusesOf(await h.history('r2')), ['inProgress']);
  });

  test('a work order move that aborts writes no entry', () async {
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

    expect(await h.history('r1'), isEmpty);
  });

  test('merging records the move on every duplicate', () async {
    await h.addReport('parent');
    await h.addReport('d1', status: ReportStatus.underReview);
    await h.addReport('d2', status: ReportStatus.underReview);

    await h.reports.mergeDuplicates(
      parentReportId: 'parent',
      duplicateReportIds: ['d1', 'd2'],
      mergedBy: admin.id,
    );

    expect(statusesOf(await h.history('d1')), ['merged']);
    expect(statusesOf(await h.history('d2')), ['merged']);
    expect(await h.history('parent'), isEmpty);
  });

  test('the history streams oldest first', () async {
    final entries = h.firestore
        .collection(FirestorePaths.damageReports)
        .doc('r1')
        .collection(FirestorePaths.statusHistory);
    await h.addReport('r1');
    for (final (status, day) in [
      (ReportStatus.approved, 3),
      (ReportStatus.submitted, 1),
      (ReportStatus.underReview, 2),
    ]) {
      await entries.add(
        StatusChange(
          id: 'x',
          status: status,
          changedAt: DateTime.utc(2026, 9, day),
          changedBy: 'admin-1',
          personnelSpecialization: status == ReportStatus.approved
              ? DamageCategory.plumbing
              : null,
        ).toFirestore(),
      );
    }

    final result = await h.reports.watchStatusHistory('r1').first;
    final history = result.fold((list) => list, (f) => fail(f.message));

    expect(history.map((change) => change.status), [
      ReportStatus.submitted,
      ReportStatus.underReview,
      ReportStatus.approved,
    ]);
    expect(history.first.changedAt, DateTime.utc(2026, 9));
    expect(history.last.personnelSpecialization, DamageCategory.plumbing);
  });
}
