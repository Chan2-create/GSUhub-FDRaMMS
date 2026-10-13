import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';

import '../support/fake_firestore_repositories.dart';
import '../support/fake_personnel_app.dart';
import '../support/fake_requestor_app.dart' show currentPath;

/// Materials a job needs (Objective 6.B): the technician asks for more
/// (Group 43), and the console pre-assigns them.
void main() {
  group('the technician (Group 43)', () {
    testWidgets('asks for materials from the work order', (tester) async {
      final app = PersonnelHarness();
      await app.seedJob(status: WorkOrderStatus.inProgress);
      await app.pump(tester, start: RoutePaths.personnelWorkOrderFor('wo-1'));

      await reveal(tester, find.text('Request Materials'));
      await tester.tap(find.text('Request Materials'));
      await tester.pumpAndSettle();
      expect(
        currentPath(tester),
        RoutePaths.personnelWorkOrderMaterialsFor('wo-1'),
      );
      expect(find.text('Pre-assigned Materials'), findsOneWidget);

      await tester.tap(find.text('Add Material'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LED Bulbs'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Quantity needed'),
        '4',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('Qty: 4 units'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Note for GSU (optional)'),
        'Two more fixtures are out.',
      );
      await reveal(tester, find.text('Submit Request'));
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      final requests = await app.data.firestore
          .collection(FirestorePaths.materialRequests)
          .get();
      final request = requests.docs.single.data();
      expect(request['status'], 'pending');
      expect(request['note'], 'Two more fixtures are out.');
      expect((request['items'] as List).single['quantity'], 4);
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('Qty: 4 units'), findsNothing);
    });

    testWidgets('sees what GSU pre-assigned on the work order', (tester) async {
      final app = PersonnelHarness();
      await app.seedJob(status: WorkOrderStatus.inProgress);
      await app.data.allocations.allocate(
        workOrderId: 'wo-1',
        inventoryItemId: 'inv-led',
        quantity: 3,
        actor: FirestoreHarness.admin,
      );
      await app.pump(tester, start: RoutePaths.personnelWorkOrderFor('wo-1'));

      await tester.scrollUntilVisible(
        find.text('Pre-assigned Materials'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('LED Bulbs'), findsWidgets);
      expect(find.text('3 units'), findsOneWidget);
    });
  });

  group('the console', () {
    testWidgets('pre-assigns a material on the work-order page', (
      tester,
    ) async {
      final app = PersonnelHarness(signedIn: fakeAdministrator);
      await app.seedJob(status: WorkOrderStatus.inProgress);
      await app.data.addPersonnel(fakeAdministrator.uid, role: UserRole.admin);
      await app.pump(
        tester,
        start: RoutePaths.adminWorkOrderDetailFor('wo-1'),
        size: const Size(1440, 1600),
      );

      await tester.ensureVisible(find.text('Pre-assigned materials'));
      await tester.tap(find.widgetWithText(InputDecorator, 'Material'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('LED Bulbs ·').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '5');
      await tester.pump();
      await tester.ensureVisible(find.text('Pre-assign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pre-assign'));
      await tester.pumpAndSettle();

      final allocated = await app.data.firestore
          .collection(FirestorePaths.workOrders)
          .doc('wo-1')
          .collection(FirestorePaths.materialsAllocated)
          .doc('inv-led')
          .get();
      expect(allocated.data()?['quantity'], 5);
      expect(find.text('Pre-assigned 5 units of LED Bulbs.'), findsOneWidget);
    });
  });
}

/// Scrolls [finder] to the middle of the page, clear of the bottom bar.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}
