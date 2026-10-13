import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/inventory_transaction_type.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/routing/route_paths.dart';

import '../support/fake_firestore_repositories.dart';
import '../support/fake_personnel_app.dart';

/// Analytics' inventory section (Objective 6.C): the materials used most
/// in the period, and the inventory report as a CSV.
void main() {
  testWidgets('ranks materials by the jobs that used them, and exports', (
    tester,
  ) async {
    final app = PersonnelHarness(signedIn: fakeAdministrator);
    await app.data.addPersonnel(fakeAdministrator.uid, role: UserRole.admin);
    await app.data.addInventoryItem('inv-led', quantity: 100, unitCost: 95);
    await app.data.addInventoryItem(
      'inv-tape',
      name: 'Insulation Tape',
      quantity: 20,
      unit: 'rolls',
    );
    Future<void> use(String itemId, double quantity, String workOrderId) =>
        app.data.inventory.recordTransaction(
          inventoryItemId: itemId,
          type: InventoryTransactionType.consumption,
          quantity: quantity,
          performedBy: FirestoreHarness.technician.id,
          performedByName: FirestoreHarness.technician.name,
          workOrderId: workOrderId,
        );
    await use('inv-tape', 1, 'w1');
    await use('inv-tape', 2, 'w2');
    await use('inv-led', 8, 'w1');

    await app.pump(
      tester,
      start: RoutePaths.adminAnalytics,
      size: const Size(1440, 2400),
    );

    expect(find.text('Most Used Materials'), findsOneWidget);
    final tape = tester.getTopLeft(find.text('INSULATION TAPE'));
    final bulbs = tester.getTopLeft(find.text('LED BULBS'));
    // The tape went on two jobs, the bulbs on one.
    expect(tape.dy, lessThan(bulbs.dy));
    expect(find.text('3 rolls · 2 jobs'), findsOneWidget);
    expect(find.text('8 units · 1 job · ₱760.00'), findsOneWidget);

    await tester.ensureVisible(find.text('Export inventory report'));
    await tester.tap(find.text('Export inventory report'));
    await tester.pumpAndSettle();

    final saved = app.downloads.saved.single;
    expect(saved.fileName, startsWith('gsuhub-inventory-last-30-days-'));
    expect(saved.contents, contains('STOCK'));
    expect(saved.contents, contains('Insulation Tape'));
    expect(saved.contents, contains('MOVEMENTS'));
    expect(saved.contents, contains('Used'));
    expect(saved.contents, contains('#WO-W1'));
  });
}
