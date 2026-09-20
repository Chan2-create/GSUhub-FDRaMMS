import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';

import '../../support/fake_firestore_repositories.dart';

/// Lifecycle guards for Objective 2.B, run against the real repositories
/// over an in-memory Firestore.
///
/// These are the tests that matter most in 2.B. A UI bug shows up on
/// screen; a transaction that commits half its writes, or lets a status
/// skip a stage, corrupts data silently and stays corrupted.
void main() {
  late FirestoreHarness h;
  const admin = FirestoreHarness.admin;

  setUp(() => h = FirestoreHarness());

  String? failureMessage(Result<Object?> result) =>
      result.fold((_) => null, (failure) => failure.message);

  group('report review transitions', () {
    test('Start review moves a submitted report and records who', () async {
      await h.addReport('r1', status: ReportStatus.submitted);

      final result = await h.reports.transitionStatus(
        reportId: 'r1',
        to: ReportStatus.underReview,
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      expect(
        (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
        'underReview',
      );

      final audit = await h.auditEntries();
      expect(audit, hasLength(1));
      expect(audit.single['actorId'], admin.id);
      expect(audit.single['actorName'], admin.name);
      expect(audit.single['entityId'], 'r1');
      expect(audit.single['changes'], {
        'from': 'submitted',
        'to': 'underReview',
      });
      expect(isTimestamp(audit.single['timestamp']), isTrue);
    });

    test('approval records the reviewer', () async {
      await h.addReport('r1', status: ReportStatus.underReview);

      await h.reports.transitionStatus(
        reportId: 'r1',
        to: ReportStatus.approved,
        actor: admin,
      );

      final report = await h.doc(FirestorePaths.damageReports, 'r1');
      expect(report['status'], 'approved');
      expect(report['reviewedBy'], admin.id);
      expect(isTimestamp(report['reviewedAt']), isTrue);
    });

    test('rejection without a reason is refused and writes nothing', () async {
      await h.addReport('r1', status: ReportStatus.underReview);

      final result = await h.reports.transitionStatus(
        reportId: 'r1',
        to: ReportStatus.rejected,
        actor: admin,
        reason: '   ',
      );

      expect(result.isFailure, isTrue);
      expect(result.fold((_) => null, (f) => f), isA<ValidationFailure>());
      expect(
        (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
        'underReview',
      );
      expect(await h.auditEntries(), isEmpty);
    });

    test('rejection stores the reason and puts it in the trail', () async {
      await h.addReport('r1', status: ReportStatus.underReview);

      await h.reports.transitionStatus(
        reportId: 'r1',
        to: ReportStatus.rejected,
        actor: admin,
        reason: '  Out of GSU scope  ',
      );

      final report = await h.doc(FirestorePaths.damageReports, 'r1');
      expect(report['status'], 'rejected');
      expect(report['rejectionReason'], 'Out of GSU scope');
      expect(
        (await h.auditEntries()).single['description'],
        'Rejected: Out of GSU scope',
      );
    });

    test('skipping review is rejected with a readable message', () async {
      await h.addReport('r1', status: ReportStatus.submitted);

      final result = await h.reports.transitionStatus(
        reportId: 'r1',
        to: ReportStatus.approved,
        actor: admin,
      );

      expect(
        failureMessage(result),
        'A report cannot move from PENDING to APPROVED.',
      );
      expect(
        (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
        'submitted',
      );
      expect(await h.auditEntries(), isEmpty);
    });

    test('later stages cannot be set without a work order', () async {
      await h.addReport('r1');

      final result = await h.reports.transitionStatus(
        reportId: 'r1',
        to: ReportStatus.assigned,
        actor: admin,
      );

      expect(failureMessage(result), contains('with its work order'));
      expect(
        (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
        'approved',
      );
    });

    test('guards against the stored status, not a stale screen', () async {
      // A second administrator already rejected it; this caller still
      // thinks it is under review.
      await h.addReport('r1', status: ReportStatus.rejected);

      final result = await h.reports.transitionStatus(
        reportId: 'r1',
        to: ReportStatus.approved,
        actor: admin,
      );

      expect(
        failureMessage(result),
        'A report cannot move from REJECTED to APPROVED.',
      );
    });
  });

  group('assignment', () {
    test(
      'creates a pending work order, assigns the report and counts it',
      () async {
        await h.addReport('r1');
        await h.addPersonnel('p1', activeTaskCount: 2);
        final target = DateTime.utc(2026, 10, 3);

        final result = await h.workOrders.assignFromReport(
          reportId: 'r1',
          personnelId: 'p1',
          actor: admin,
          scheduledFor: target,
        );

        final workOrderId = result.fold((id) => id, (f) => fail(f.message));
        final workOrder = await h.doc(FirestorePaths.workOrders, workOrderId);
        expect(workOrder['status'], 'pending');
        expect(workOrder['reportIds'], ['r1']);
        expect(workOrder['assignedPersonnelIds'], ['p1']);
        expect(workOrder['category'], 'electrical');
        expect(workOrder['priority'], 'high');
        expect(workOrder['createdBy'], admin.id);
        expect(workOrder['facilityName'], 'Engineering Building');
        // The optional target completion date becomes the work order's
        // schedule, which is what OVERDUE is measured against.
        expect(
          (workOrder['scheduledFor'] as Timestamp).toDate().toUtc(),
          target,
        );

        final report = await h.doc(FirestorePaths.damageReports, 'r1');
        expect(report['status'], 'assigned');
        expect(report['workOrderId'], workOrderId);

        expect((await h.doc(FirestorePaths.users, 'p1'))['activeTaskCount'], 3);

        final audit = await h.auditEntries();
        expect(
          audit.map((e) => e['action']),
          containsAll(['assigned', 'created']),
        );
        expect(audit.every((e) => e['actorId'] == admin.id), isTrue);
      },
    );

    test('assignment works without a target date', () async {
      await h.addReport('r1');
      await h.addPersonnel('p1');

      final withoutDate = await h.workOrders.assignFromReport(
        reportId: 'r1',
        personnelId: 'p1',
        actor: admin,
      );

      final id = withoutDate.fold((id) => id, (f) => fail(f.message));
      expect(
        (await h.doc(FirestorePaths.workOrders, id))['scheduledFor'],
        isNull,
      );
    });

    Future<void> expectNothingWritten() async {
      expect(await h.count(FirestorePaths.workOrders), 0);
      expect(await h.auditEntries(), isEmpty);
    }

    test('refuses a report that has not been approved', () async {
      await h.addReport('r1', status: ReportStatus.underReview);
      await h.addPersonnel('p1');

      final result = await h.workOrders.assignFromReport(
        reportId: 'r1',
        personnelId: 'p1',
        actor: admin,
      );

      expect(failureMessage(result), contains('Only approved reports'));
      expect(failureMessage(result), contains('UNDER REVIEW'));
      await expectNothingWritten();
      expect((await h.doc(FirestorePaths.users, 'p1'))['activeTaskCount'], 0);
    });

    test(
      'refuses an unclassified report rather than inventing a trade',
      () async {
        await h.addReport('r1', category: null);
        await h.addPersonnel('p1');

        final result = await h.workOrders.assignFromReport(
          reportId: 'r1',
          personnelId: 'p1',
          actor: admin,
        );

        expect(failureMessage(result), contains('no damage category'));
        await expectNothingWritten();
      },
    );

    test('refuses a report that already has a work order', () async {
      await h.addReport('r1', workOrderId: 'existing');
      await h.addPersonnel('p1');

      final result = await h.workOrders.assignFromReport(
        reportId: 'r1',
        personnelId: 'p1',
        actor: admin,
      );

      expect(failureMessage(result), 'This report already has a work order.');
      await expectNothingWritten();
    });

    test('refuses an inactive account', () async {
      await h.addReport('r1');
      await h.addPersonnel('p1', accountStatus: AccountStatus.inactive);

      final result = await h.workOrders.assignFromReport(
        reportId: 'r1',
        personnelId: 'p1',
        actor: admin,
      );

      expect(failureMessage(result), contains('inactive'));
      await expectNothingWritten();
      expect(
        (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
        'approved',
      );
    });

    test('refuses someone who is not maintenance personnel', () async {
      await h.addReport('r1');
      await h.addPersonnel('p1', role: UserRole.requestor);

      final result = await h.workOrders.assignFromReport(
        reportId: 'r1',
        personnelId: 'p1',
        actor: admin,
      );

      expect(failureMessage(result), contains('not maintenance personnel'));
      await expectNothingWritten();
    });
  });

  group('work order status', () {
    test('starting work moves the linked report with it', () async {
      await h.addReport('r1', status: ReportStatus.assigned, workOrderId: 'w1');
      await h.addWorkOrder(
        'w1',
        reportIds: ['r1'],
        status: WorkOrderStatus.pending,
      );

      final result = await h.workOrders.setStatus(
        'w1',
        WorkOrderStatus.inProgress,
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      final workOrder = await h.doc(FirestorePaths.workOrders, 'w1');
      expect(workOrder['status'], 'inProgress');
      expect(isTimestamp(workOrder['startedAt']), isTrue);
      expect(
        (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
        'inProgress',
      );
      expect((await h.auditEntries()).single['actorId'], admin.id);
    });

    test('an invalid move is rejected with the column names', () async {
      await h.addReport('r1', status: ReportStatus.assigned, workOrderId: 'w1');
      await h.addWorkOrder(
        'w1',
        reportIds: ['r1'],
        status: WorkOrderStatus.pending,
      );

      final result = await h.workOrders.setStatus(
        'w1',
        WorkOrderStatus.completed,
        actor: admin,
      );

      expect(
        failureMessage(result),
        'A work order cannot move from Pending to Completed.',
      );
      expect(
        (await h.doc(FirestorePaths.workOrders, 'w1'))['status'],
        'pending',
      );
      expect(
        (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
        'assigned',
      );
      expect(await h.auditEntries(), isEmpty);
    });

    test('completion releases the assignee and completes the report', () async {
      await h.addPersonnel('p1', activeTaskCount: 2);
      await h.addReport(
        'r1',
        status: ReportStatus.forReview,
        workOrderId: 'w1',
      );
      await h.addWorkOrder(
        'w1',
        reportIds: ['r1'],
        status: WorkOrderStatus.forReview,
        assignedPersonnelIds: ['p1'],
      );

      await h.workOrders.setStatus(
        'w1',
        WorkOrderStatus.completed,
        actor: admin,
      );

      expect((await h.doc(FirestorePaths.users, 'p1'))['activeTaskCount'], 1);
      expect(
        (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
        'completed',
      );
      expect(
        isTimestamp(
          (await h.doc(FirestorePaths.workOrders, 'w1'))['completedAt'],
        ),
        isTrue,
      );
    });

    test('releasing a count never takes it below zero', () async {
      // A count already at zero means the data was off before this move.
      // Going negative would make AppUser refuse to load the person at all.
      await h.addPersonnel('p1');
      await h.addReport(
        'r1',
        status: ReportStatus.forReview,
        workOrderId: 'w1',
      );
      await h.addWorkOrder(
        'w1',
        reportIds: ['r1'],
        status: WorkOrderStatus.forReview,
        assignedPersonnelIds: ['p1'],
      );

      await h.workOrders.setStatus(
        'w1',
        WorkOrderStatus.completed,
        actor: admin,
      );

      expect((await h.doc(FirestorePaths.users, 'p1'))['activeTaskCount'], 0);
    });

    test('rework sends the order and its report back to in progress', () async {
      await h.addReport(
        'r1',
        status: ReportStatus.forReview,
        workOrderId: 'w1',
      );
      await h.addWorkOrder(
        'w1',
        reportIds: ['r1'],
        status: WorkOrderStatus.forReview,
      );

      final result = await h.workOrders.setStatus(
        'w1',
        WorkOrderStatus.inProgress,
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      expect(
        (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
        'inProgress',
      );
    });

    test('a report that cannot follow aborts the whole move', () async {
      // The report was rejected out from under its work order. Moving the
      // order anyway would leave the two permanently disagreeing.
      await h.addReport('r1', status: ReportStatus.rejected, workOrderId: 'w1');
      await h.addWorkOrder(
        'w1',
        reportIds: ['r1'],
        status: WorkOrderStatus.pending,
      );

      final result = await h.workOrders.setStatus(
        'w1',
        WorkOrderStatus.inProgress,
        actor: admin,
      );

      expect(failureMessage(result), contains('cannot move to IN PROGRESS'));
      expect(
        (await h.doc(FirestorePaths.workOrders, 'w1'))['status'],
        'pending',
      );
      expect(await h.auditEntries(), isEmpty);
    });
  });
}
