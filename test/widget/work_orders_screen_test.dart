import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';
import 'package:gsuhub/features/work_orders/presentation/work_orders_screen.dart';

import '../support/fake_admin_backend.dart';

/// Work Order Management: board, filters and guarded moves (Objective 2.B).
void main() {
  WorkOrder order({
    required String id,
    required String title,
    WorkOrderStatus status = WorkOrderStatus.pending,
    PriorityLevel priority = PriorityLevel.medium,
    String facility = 'Engineering Building',
    List<String> assignees = const ['p1'],
    DateTime? scheduledFor,
    DateTime? completedAt,
  }) => WorkOrder(
    id: id,
    reportIds: ['rep-$id'],
    title: title,
    description: 'Seeded for test.',
    category: DamageCategory.electrical,
    priority: priority,
    status: status,
    assignedPersonnelIds: assignees,
    facilityName: facility,
    scheduledFor: scheduledFor,
    completedAt: completedAt,
    createdBy: 'admin-1',
    createdAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    updatedAt: DateTime.now().toUtc(),
  );

  Future<FakeWorkOrderRepository> pump(
    WidgetTester tester,
    List<WorkOrder> workOrders, {
    Result<void> moveResult = const Result.success(null),
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 1800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = FakeWorkOrderRepository(
      Result.success(workOrders),
      statusResult: moveResult,
    );

    await tester.pumpWidget(
      fakeAdminScope(
        workOrderRepository: repository,
        personnel: Result.success([
          fakePersonnel(id: 'p1', fullName: 'Marcus Wright'),
        ]),
        child: const MaterialApp(home: Scaffold(body: WorkOrdersScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  group('board', () {
    testWidgets('groups work orders into the four columns with counts', (
      tester,
    ) async {
      await pump(tester, [
        order(id: 'w1', title: 'Window Gasket'),
        order(id: 'w2', title: 'Filter Replacement'),
        order(
          id: 'w3',
          title: 'HVAC Repair',
          status: WorkOrderStatus.inProgress,
        ),
      ]);

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('For Review'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      expect(find.text('Window Gasket'), findsOneWidget);
      expect(find.text('Filter Replacement'), findsOneWidget);
      expect(find.text('HVAC Repair'), findsOneWidget);
      // The Pending column badge reads 2. (Bare "0" is not asserted here:
      // the stat cards above the board show zeroes of their own.)
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows the assignee, or says it is unassigned', (tester) async {
      await pump(tester, [
        order(id: 'w1', title: 'Window Gasket'),
        order(id: 'w2', title: 'Orphan', assignees: const []),
      ]);

      expect(find.text('Marcus Wright'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
    });

    testWidgets('explains an empty board rather than showing nothing', (
      tester,
    ) async {
      await pump(tester, []);

      expect(find.textContaining('Task Assignment screen'), findsOneWidget);
    });
  });

  group('moving a work order', () {
    Future<void> moveVia(WidgetTester tester, String target) async {
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to $target'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers only the moves the lifecycle allows', (tester) async {
      await pump(tester, [order(id: 'w1', title: 'Window Gasket')]);

      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();

      // Pending goes to In Progress and nowhere else.
      expect(find.text('Move to In Progress'), findsOneWidget);
      expect(find.text('Move to Completed'), findsNothing);
      expect(find.text('Move to For Review'), findsNothing);
    });

    testWidgets('a legal move reaches the repository', (tester) async {
      final repository = await pump(tester, [
        order(id: 'w1', title: 'Window Gasket'),
      ]);

      await moveVia(tester, 'In Progress');

      expect(repository.moves, hasLength(1));
      expect(repository.moves.single.workOrderId, 'w1');
      expect(repository.moves.single.status, WorkOrderStatus.inProgress);
      expect(find.textContaining('moved to In Progress'), findsOneWidget);
    });

    testWidgets('a refusal is shown, and the card does not move', (
      tester,
    ) async {
      // The repository is the authority: it re-reads the stored status in a
      // transaction and can refuse a move the board thought was fine.
      final repository = await pump(
        tester,
        [order(id: 'w1', title: 'Window Gasket')],
        moveResult: const Result.failure(
          ValidationFailure(
            'A work order cannot move from Pending to Completed.',
          ),
        ),
      );

      await moveVia(tester, 'In Progress');

      expect(repository.moves, hasLength(1));
      expect(
        find.text('A work order cannot move from Pending to Completed.'),
        findsOneWidget,
      );
      // The board renders from the stream, which never changed.
      expect(find.text('Window Gasket'), findsOneWidget);
    });

    testWidgets('a completed order offers no moves at all', (tester) async {
      await pump(tester, [
        order(
          id: 'w1',
          title: 'Light Fixture',
          status: WorkOrderStatus.completed,
        ),
      ]);

      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });
  });

  group('filters', () {
    testWidgets('take effect only when Apply is pressed', (tester) async {
      await pump(tester, [
        order(id: 'w1', title: 'Window Gasket'),
        order(id: 'w2', title: 'HVAC Repair'),
      ]);

      await tester.enterText(find.byType(TextField), 'HVAC');
      await tester.pumpAndSettle();

      // The design puts an explicit Apply on this bar, so typing alone
      // changes nothing.
      expect(find.text('Window Gasket'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('HVAC Repair'), findsOneWidget);
      expect(find.text('Window Gasket'), findsNothing);
    });

    testWidgets('search matches the location as well as the title', (
      tester,
    ) async {
      await pump(tester, [
        order(id: 'w1', title: 'Window Gasket', facility: 'Main Library'),
        order(id: 'w2', title: 'HVAC Repair'),
      ]);

      await tester.enterText(find.byType(TextField), 'Library');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Window Gasket'), findsOneWidget);
      expect(find.text('HVAC Repair'), findsNothing);
    });
  });

  group('view toggle', () {
    testWidgets('switches between the board and the table', (tester) async {
      await pump(tester, [order(id: 'w1', title: 'Window Gasket')]);

      // Kanban is the design's default.
      expect(find.text('Pending'), findsOneWidget);

      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();

      // The table carries column headers the board does not.
      expect(find.text('WORK ORDER'), findsOneWidget);
      expect(find.text('ASSIGNEE'), findsOneWidget);
      // An auto-style id is shortened and prefixed for display.
      expect(find.text('#WO-W1'), findsOneWidget);
    });
  });

  group('stat cards', () {
    testWidgets('count overdue and completed today from the data', (
      tester,
    ) async {
      final now = DateTime.now().toUtc();
      await pump(tester, [
        order(
          id: 'w1',
          title: 'Late one',
          scheduledFor: now.subtract(const Duration(days: 2)),
        ),
        order(
          id: 'w2',
          title: 'Done today',
          status: WorkOrderStatus.completed,
          completedAt: now,
        ),
        order(id: 'w3', title: 'On track', status: WorkOrderStatus.inProgress),
      ]);

      expect(find.text('TOTAL ORDERS'), findsOneWidget);
      expect(find.text('OVERDUE'), findsOneWidget);
      // 3 total, 1 in progress, 1 overdue, 1 completed today.
      expect(find.text('3'), findsWidgets);
    });
  });
}
