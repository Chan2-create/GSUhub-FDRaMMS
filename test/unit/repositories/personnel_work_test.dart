import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/task_status.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/accomplishment/data/models/material_usage.dart';

import '../../support/fake_firestore_repositories.dart';

/// The personnel app's work (Objectives 5.A–5.C), against the real
/// repositories over an in-memory Firestore: tasks, starting and filing
/// the work, the materials it used, the tools borrowed for it, and the
/// administrator's review.
void main() {
  late FirestoreHarness h;
  const admin = FirestoreHarness.admin;
  const technician = FirestoreHarness.technician;

  setUp(() => h = FirestoreHarness());

  String? failureMessage(Result<Object?> result) =>
      result.fold((_) => null, (failure) => failure.message);

  Future<Map<String, dynamic>> doc(String collection, String id) =>
      h.doc(collection, id);

  /// A report and its work order, assigned to [technician].
  Future<void> addWork(
    WorkOrderStatus status, {
    String workOrderId = 'w1',
    String reportId = 'r1',
  }) async {
    await h.addReport(
      reportId,
      status: WorkOrderMoveStatuses.reportFor(status),
      workOrderId: workOrderId,
    );
    await h.addWorkOrder(workOrderId, reportIds: [reportId], status: status);
  }

  Future<List<Map<String, dynamic>>> notices(String recipient) async => [
    for (final notice in await h.notifications())
      if (notice['recipientId'] == recipient) notice,
  ];

  group('assignment (5.A)', () {
    test(
      'creates the first task, the job itself, due on the target date',
      () async {
        await h.addReport('r1');
        await h.addPersonnel('p1');
        final target = DateTime.utc(2026, 10, 3, 12);

        final result = await h.workOrders.assignFromReport(
          reportId: 'r1',
          personnelId: 'p1',
          actor: admin,
          scheduledFor: target,
        );
        final workOrderId = result.fold((id) => id, (f) => fail(f.message));

        final tasks = await h.firestore.collection(FirestorePaths.tasks).get();
        final task = tasks.docs.single.data();
        expect(task['workOrderId'], workOrderId);
        expect(task['title'], 'Flickering lights');
        expect(task['assignedTo'], 'p1');
        expect(task['status'], 'pending');
        expect((task['dueDate'] as Timestamp).toDate().toUtc(), target);
      },
    );
  });

  group('tasks', () {
    test('an administrator adds one; the technician is told', () async {
      await addWork(WorkOrderStatus.inProgress);

      final result = await h.tasks.addTask(
        workOrderId: 'w1',
        title: '  Test every fixture  ',
        description: 'On the circuit',
        dueDate: DateTime.utc(2026, 10, 4, 12),
        actor: admin,
      );
      final id = result.fold((id) => id, (f) => fail(f.message));

      final task = await doc(FirestorePaths.tasks, id);
      expect(task['title'], 'Test every fixture');
      expect(task['assignedTo'], 'personnel-1');
      expect(task['status'], 'pending');

      final notice = (await notices('personnel-1')).single;
      expect(notice['type'], 'taskAssigned');
      expect(notice['relatedEntityType'], 'work_orders');
      expect(notice['relatedEntityId'], 'w1');
      expect(
        (await h.auditEntries()).single['description'],
        'Task "Test every fixture" added to #WO-W1',
      );
    });

    test(
      'none can be added once the work is submitted or signed off',
      () async {
        for (final status in [
          WorkOrderStatus.forReview,
          WorkOrderStatus.completed,
        ]) {
          await addWork(status, workOrderId: 'w-${status.id}');
          final result = await h.tasks.addTask(
            workOrderId: 'w-${status.id}',
            title: 'Late task',
            actor: admin,
          );
          expect(failureMessage(result), contains('no task can be added'));
        }
      },
    );

    test('a task needs a title', () async {
      await addWork(WorkOrderStatus.pending);

      final result = await h.tasks.addTask(
        workOrderId: 'w1',
        title: '   ',
        actor: admin,
      );

      expect(failureMessage(result), 'Give the task a title.');
    });

    test('a task not done can be removed; a done one stays', () async {
      await addWork(WorkOrderStatus.inProgress);
      await h.addTask('t1', workOrderId: 'w1');
      await h.addTask('t2', workOrderId: 'w1', status: TaskStatus.completed);

      expect(
        (await h.tasks.deleteTask(taskId: 't1', actor: admin)).isSuccess,
        isTrue,
      );
      expect(await doc(FirestorePaths.tasks, 't1'), isEmpty);
      expect(
        failureMessage(await h.tasks.deleteTask(taskId: 't2', actor: admin)),
        contains('stays on the record'),
      );
    });

    test('ticking one done records when', () async {
      await addWork(WorkOrderStatus.inProgress);
      await h.addTask('t1', workOrderId: 'w1');

      final result = await h.tasks.setStatus(
        taskId: 't1',
        status: TaskStatus.completed,
        actor: technician,
      );

      expect(result.isSuccess, isTrue);
      final task = await doc(FirestorePaths.tasks, 't1');
      expect(task['status'], 'completed');
      expect(isTimestamp(task['completedAt']), isTrue);
      // Tasks leave the open-work count alone: it counts work orders.
      expect(await doc(FirestorePaths.users, 'personnel-1'), isEmpty);
    });

    test('the first task touched starts a pending work order, and the '
        "requestor's report with it", () async {
      await addWork(WorkOrderStatus.pending);
      await h.addTask('t1', workOrderId: 'w1');

      await h.tasks.setStatus(
        taskId: 't1',
        status: TaskStatus.completed,
        actor: technician,
      );

      final workOrder = await doc(FirestorePaths.workOrders, 'w1');
      expect(workOrder['status'], 'inProgress');
      expect(isTimestamp(workOrder['startedAt']), isTrue);
      expect(
        (await doc(FirestorePaths.damageReports, 'r1'))['status'],
        'inProgress',
      );
      expect((await h.history('r1')).single['status'], 'inProgress');
      expect((await notices('faculty-1')).single['title'], 'Work started');
    });

    test('tasks no longer change once the work is submitted', () async {
      await addWork(WorkOrderStatus.forReview);
      await h.addTask('t1', workOrderId: 'w1');

      final result = await h.tasks.setStatus(
        taskId: 't1',
        status: TaskStatus.completed,
        actor: technician,
      );

      expect(failureMessage(result), contains('can no longer change'));
      expect((await doc(FirestorePaths.tasks, 't1'))['status'], 'pending');
    });

    test('proof photos are added, and put the task in progress', () async {
      await addWork(WorkOrderStatus.inProgress);
      await h.addTask('t1', workOrderId: 'w1');

      await h.tasks.addProofPhotos(
        taskId: 't1',
        photoUrls: ['https://storage.test/a.jpg'],
        actor: technician,
      );
      await h.tasks.addProofPhotos(
        taskId: 't1',
        photoUrls: ['https://storage.test/b.jpg'],
        actor: technician,
      );

      final task = await doc(FirestorePaths.tasks, 't1');
      expect(task['proofPhotoUrls'], [
        'https://storage.test/a.jpg',
        'https://storage.test/b.jpg',
      ]);
      expect(task['status'], 'inProgress');
    });
  });

  group('materials recorded (5.C)', () {
    test('records an amount, and a second record replaces it', () async {
      await addWork(WorkOrderStatus.inProgress);
      await h.addInventoryItem('inv-1');

      for (final quantity in [3.0, 2.0]) {
        await h.materials.record(
          workOrderId: 'w1',
          inventoryItemId: 'inv-1',
          quantity: quantity,
          actor: technician,
        );
      }

      final recorded = (await h.materials.watchForWorkOrder('w1').first).fold(
        (list) => list,
        (f) => fail(f.message),
      );
      expect(recorded.single.usage.itemName, 'LED Bulbs');
      expect(recorded.single.usage.quantityUsed, 2);
      expect(recorded.single.recordedBy, 'personnel-1');
      // Stock is untouched until the report is filed.
      expect(
        (await doc(
          FirestorePaths.inventoryItems,
          'inv-1',
        ))['quantityAvailable'],
        10,
      );
    });

    test(
      'refuses more than is in stock, and work not yours or closed',
      () async {
        await addWork(WorkOrderStatus.inProgress);
        await addWork(
          WorkOrderStatus.forReview,
          workOrderId: 'w2',
          reportId: 'r2',
        );
        await h.addInventoryItem('inv-1', quantity: 1);

        expect(
          failureMessage(
            await h.materials.record(
              workOrderId: 'w1',
              inventoryItemId: 'inv-1',
              quantity: 2,
              actor: technician,
            ),
          ),
          'Only 1 units of LED Bulbs in stock.',
        );
        expect(
          failureMessage(
            await h.materials.record(
              workOrderId: 'w2',
              inventoryItemId: 'inv-1',
              quantity: 1,
              actor: technician,
            ),
          ),
          contains('can no longer be recorded'),
        );
        expect(
          failureMessage(
            await h.materials.record(
              workOrderId: 'w1',
              inventoryItemId: 'inv-1',
              quantity: 1,
              actor: admin,
            ),
          ),
          'This work order is not assigned to you.',
        );
      },
    );
  });

  group('accomplishment report (5.B)', () {
    Future<Result<void>> submit({
      String reportId = 'acc-1',
      List<MaterialUsage> materials = const [],
      List<String> photos = const ['https://storage.test/done.jpg'],
      String notes = 'Replaced the ballast; all lights steady.',
    }) => h.accomplishments.submit(
      reportId: reportId,
      workOrderId: 'w1',
      completionNotes: notes,
      photoUrls: photos,
      materialsUsed: materials,
      actor: technician,
    );

    MaterialUsage leds(double quantity) => MaterialUsage(
      inventoryItemId: 'inv-1',
      itemName: 'LED Bulbs',
      quantityUsed: quantity,
      unitOfMeasurement: 'units',
    );

    test('files it, deducts the materials, and sends the work for '
        'sign-off', () async {
      await addWork(WorkOrderStatus.inProgress);
      await h.addInventoryItem('inv-1');
      await h.materials.record(
        workOrderId: 'w1',
        inventoryItemId: 'inv-1',
        quantity: 4,
        actor: technician,
      );

      final result = await submit(materials: [leds(4)]);

      expect(result.isSuccess, isTrue);
      final report = await doc(FirestorePaths.accomplishmentReports, 'acc-1');
      expect(report['submittedBy'], 'personnel-1');
      expect(report['inventoryDeducted'], isTrue);
      expect(report['materialsUsed'], hasLength(1));
      expect(isTimestamp(report['submittedAt']), isTrue);

      expect(
        (await doc(
          FirestorePaths.inventoryItems,
          'inv-1',
        ))['quantityAvailable'],
        6,
      );
      final ledger = await h.firestore
          .collection(FirestorePaths.inventoryTransactions)
          .get();
      final entry = ledger.docs.single.data();
      expect(entry['type'], 'consumption');
      expect(entry['quantity'], 4);
      expect(entry['quantityBefore'], 10);
      expect(entry['quantityAfter'], 6);
      expect(entry['accomplishmentReportId'], 'acc-1');
      expect(entry['workOrderId'], 'w1');

      // The recorded line is cleared once deducted.
      expect(
        (await h.materials.watchForWorkOrder('w1').first).fold(
          (list) => list,
          (f) => fail(f.message),
        ),
        isEmpty,
      );
      expect(
        (await doc(FirestorePaths.workOrders, 'w1'))['status'],
        'forReview',
      );
      expect(
        (await doc(FirestorePaths.damageReports, 'r1'))['status'],
        'forReview',
      );
      expect((await h.history('r1')).single['status'], 'forReview');
    });

    test('a retry files nothing twice and deducts nothing twice', () async {
      await addWork(WorkOrderStatus.inProgress);
      await h.addInventoryItem('inv-1');

      await submit(materials: [leds(4)]);
      final retry = await submit(materials: [leds(4)]);

      expect(retry.isSuccess, isTrue);
      expect(await h.count(FirestorePaths.accomplishmentReports), 1);
      expect(await h.count(FirestorePaths.inventoryTransactions), 1);
      expect(
        (await doc(
          FirestorePaths.inventoryItems,
          'inv-1',
        ))['quantityAvailable'],
        6,
      );
    });

    test('refuses work not yet started, and changes nothing', () async {
      await addWork(WorkOrderStatus.pending);

      expect(
        failureMessage(await submit()),
        'Start the work before marking it complete.',
      );
      expect(await h.count(FirestorePaths.accomplishmentReports), 0);
    });

    test('refuses when a material is short, and deducts nothing', () async {
      await addWork(WorkOrderStatus.inProgress);
      await h.addInventoryItem('inv-1', quantity: 2);

      expect(
        failureMessage(await submit(materials: [leds(4)])),
        contains('Not enough LED Bulbs in stock'),
      );
      expect(await h.count(FirestorePaths.accomplishmentReports), 0);
      expect(
        (await doc(
          FirestorePaths.inventoryItems,
          'inv-1',
        ))['quantityAvailable'],
        2,
      );
      expect(
        (await doc(FirestorePaths.workOrders, 'w1'))['status'],
        'inProgress',
      );
    });

    test('needs notes and a photo', () async {
      await addWork(WorkOrderStatus.inProgress);

      expect(
        failureMessage(await submit(notes: '  ')),
        'Describe the work that was done.',
      );
      expect(
        failureMessage(await submit(photos: const [])),
        'Add at least one photo of the finished work.',
      );
    });

    test('approved: the work is signed off and the technician told', () async {
      await addWork(WorkOrderStatus.inProgress);
      await h.addPersonnel('personnel-1', activeTaskCount: 1);
      await submit();

      final result = await h.accomplishments.review(
        reportId: 'acc-1',
        approve: true,
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      final report = await doc(FirestorePaths.accomplishmentReports, 'acc-1');
      expect(report['reviewedBy'], admin.id);
      expect(isTimestamp(report['reviewedAt']), isTrue);
      final workOrder = await doc(FirestorePaths.workOrders, 'w1');
      expect(workOrder['status'], 'completed');
      expect(isTimestamp(workOrder['completedAt']), isTrue);
      expect(
        (await doc(FirestorePaths.damageReports, 'r1'))['status'],
        'completed',
      );
      expect(
        (await doc(FirestorePaths.users, 'personnel-1'))['activeTaskCount'],
        0,
      );
      expect((await notices('personnel-1')).single['title'], 'Work signed off');
    });

    test('sent back: the work reopens with the note on it', () async {
      await addWork(WorkOrderStatus.inProgress);
      await submit();

      await h.accomplishments.review(
        reportId: 'acc-1',
        approve: false,
        note: 'Two clips are loose.',
        actor: admin,
      );

      final workOrder = await doc(FirestorePaths.workOrders, 'w1');
      expect(workOrder['status'], 'inProgress');
      expect(workOrder['adminNotes'], 'Two clips are loose.');
      expect(
        (await doc(FirestorePaths.damageReports, 'r1'))['status'],
        'inProgress',
      );
      expect((await notices('personnel-1')).single['title'], 'Work sent back');
    });

    test('a report is reviewed once', () async {
      await addWork(WorkOrderStatus.inProgress);
      await submit();
      await h.accomplishments.review(
        reportId: 'acc-1',
        approve: false,
        actor: admin,
      );

      final again = await h.accomplishments.review(
        reportId: 'acc-1',
        approve: true,
        actor: admin,
      );

      expect(failureMessage(again), contains('reviewed already'));
    });
  });

  group('tools (5.C)', () {
    test('borrowing records the loan, the holder and an audit entry', () async {
      await h.addTool('tool-1');

      final result = await h.tools.borrowTool(
        toolId: 'tool-1',
        borrower: technician,
        workOrderId: 'w1',
      );

      final loan = result.fold((loan) => loan, (f) => fail(f.message));
      final tool = await doc(FirestorePaths.tools, 'tool-1');
      expect(tool['status'], 'borrowed');
      expect(tool['currentHolderId'], 'personnel-1');
      expect(tool['currentLoanId'], loan.id);
      expect(
        (await h.auditEntries()).single['description'],
        'Borrowed Fluke Multimeter for #WO-W1',
      );
      final open = (await h.tools.watchOpenLoansFor('personnel-1').first).fold(
        (list) => list,
        (f) => fail(f.message),
      );
      expect(open.single.toolId, 'tool-1');
    });

    test('a tool already out cannot be borrowed', () async {
      await h.addTool('tool-1', status: ToolStatus.borrowed);

      final result = await h.tools.borrowTool(
        toolId: 'tool-1',
        borrower: technician,
      );

      expect(
        failureMessage(result),
        'Fluke Multimeter cannot be borrowed: it '
        'is borrowed.',
      );
    });

    test('returned in poor condition, it goes to repair', () async {
      await h.addTool('tool-1');
      final loan = (await h.tools.borrowTool(
        toolId: 'tool-1',
        borrower: technician,
      )).fold((loan) => loan, (f) => fail(f.message));

      final result = await h.tools.returnTool(
        loanId: loan.id,
        conditionOnReturn: ItemCondition.poor,
        actor: technician,
      );

      expect(result.isSuccess, isTrue);
      final tool = await doc(FirestorePaths.tools, 'tool-1');
      expect(tool['status'], 'inRepair');
      expect(tool['condition'], 'poor');
      expect(tool['currentHolderId'], isNull);
      expect(
        (await h.tools.watchOpenLoansFor('personnel-1').first).fold(
          (list) => list,
          (f) => fail(f.message),
        ),
        isEmpty,
      );
    });
  });

  test(
    "an administrator's note to the technician is saved and audited",
    () async {
      await addWork(WorkOrderStatus.inProgress);

      await h.workOrders.updateAdminNotes(
        workOrderId: 'w1',
        notes: '  Please finish before 2 PM.  ',
        actor: admin,
      );
      expect(
        (await doc(FirestorePaths.workOrders, 'w1'))['adminNotes'],
        'Please finish before 2 PM.',
      );

      await h.workOrders.updateAdminNotes(
        workOrderId: 'w1',
        notes: '',
        actor: admin,
      );
      expect(
        (await doc(FirestorePaths.workOrders, 'w1'))['adminNotes'],
        isNull,
      );
      expect(await h.auditEntries(), hasLength(2));
    },
  );
}

/// The report status that goes with each work-order status.
abstract final class WorkOrderMoveStatuses {
  static ReportStatus reportFor(WorkOrderStatus status) => switch (status) {
    WorkOrderStatus.pending => ReportStatus.assigned,
    WorkOrderStatus.inProgress => ReportStatus.inProgress,
    WorkOrderStatus.forReview => ReportStatus.forReview,
    WorkOrderStatus.completed => ReportStatus.completed,
  };
}
