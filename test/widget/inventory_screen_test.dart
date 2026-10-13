import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/inventory/data/models/material_line.dart';

import '../support/fake_firestore_repositories.dart';
import '../support/fake_personnel_app.dart';

/// The console's Inventory Management page (Objectives 6.A–6.B, Figure
/// 15), over an in-memory Firestore: what it shows, and what each button
/// writes.
void main() {
  Future<PersonnelHarness> console(WidgetTester tester) async {
    final app = PersonnelHarness(signedIn: fakeAdministrator);
    await app.data.addPersonnel(fakeAdministrator.uid, role: UserRole.admin);
    await app.data.addPersonnel(fakeTechnician.uid);
    await app.data.addInventoryItem(
      'inv-led',
      quantity: 40,
      minimum: 10,
      unitCost: 100,
    );
    await app.data.addInventoryItem(
      'inv-tape',
      name: 'Insulation Tape',
      quantity: 2,
      unit: 'rolls',
      minimum: 5,
      unitCost: 50,
    );
    await app.data.addTool('tool-1');
    return app;
  }

  Future<void> pump(PersonnelHarness app, WidgetTester tester) => app.pump(
    tester,
    start: RoutePaths.adminInventory,
    size: const Size(1440, 1400),
  );

  double? stock(Map<String, dynamic> item) =>
      (item['quantityAvailable'] as num?)?.toDouble();

  testWidgets('the cards add up the stock, the alerts, the loans', (
    tester,
  ) async {
    final app = await console(tester);
    await pump(app, tester);

    expect(find.text('Total Stock Value'), findsOneWidget);
    // 40 × ₱100 + 2 × ₱50.
    expect(find.text('₱4,100'), findsOneWidget);
    expect(find.text('Across 2 materials'), findsOneWidget);
    expect(find.text('Low Stock Alerts'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('Action required soon'), findsOneWidget);
    expect(find.text('Of 1 tools in total'), findsOneWidget);
  });

  testWidgets('a low material offers ORDER, which records a delivery', (
    tester,
  ) async {
    final app = await console(tester);
    await pump(app, tester);

    expect(find.text('LOW STOCK'), findsOneWidget);
    expect(find.text('IN STOCK'), findsOneWidget);
    await tester.tap(find.text('ORDER'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Quantity received'),
      '10',
    );
    await tester.tap(find.text('Record delivery'));
    await tester.pumpAndSettle();

    expect(
      stock(await app.read(FirestorePaths.inventoryItems, 'inv-tape')),
      12,
    );
    expect(
      find.text('Recorded 10 rolls of Insulation Tape received.'),
      findsOneWidget,
    );
    // No longer low: the alert clears.
    expect(find.text('LOW STOCK'), findsNothing);
  });

  testWidgets('Add Material registers one with its opening stock', (
    tester,
  ) async {
    final app = await console(tester);
    await pump(app, tester);

    await tester.tap(find.text('Add Material'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Wall Socket Plate',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Category'),
      'Electrical',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Alert when at or below'),
      '5',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Opening stock'),
      '20',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add material'));
    await tester.pumpAndSettle();

    final items = await app.data.firestore
        .collection(FirestorePaths.inventoryItems)
        .where('name', isEqualTo: 'Wall Socket Plate')
        .get();
    final item = items.docs.single.data();
    expect(item['qrCode'], 'INV-WALL-SOCKET-PLATE');
    expect(item['quantityAvailable'], 20);
    expect(find.text('Wall Socket Plate'), findsOneWidget);
  });

  testWidgets('a tool is checked out to a technician, then checked in', (
    tester,
  ) async {
    final app = await console(tester);
    await pump(app, tester);

    await tester.ensureVisible(find.text('Check Out'));
    await tester.tap(find.text('Check Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Technician'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcus Wright').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check out'));
    await tester.pumpAndSettle();

    var tool = await app.read(FirestorePaths.tools, 'tool-1');
    expect(tool['status'], ToolStatus.borrowed.id);
    expect(tool['currentHolderId'], fakeTechnician.uid);
    expect(find.text('BORROWED'), findsOneWidget);

    await tester.ensureVisible(find.text('Check In'));
    await tester.tap(find.text('Check In'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check in'));
    await tester.pumpAndSettle();

    tool = await app.read(FirestorePaths.tools, 'tool-1');
    expect(tool['status'], ToolStatus.available.id);
  });

  testWidgets('a waiting request is approved onto its work order', (
    tester,
  ) async {
    final app = await console(tester);
    await app.data.addReport('r1', workOrderId: 'w1');
    await app.data.addWorkOrder(
      'w1',
      reportIds: ['r1'],
      status: WorkOrderStatus.inProgress,
    );
    await app.data.requests.submit(
      requestId: 'rq-1',
      workOrderId: 'w1',
      items: [
        MaterialLine(
          inventoryItemId: 'inv-led',
          itemName: 'LED Bulbs',
          quantity: 4,
          unitOfMeasurement: 'units',
        ),
      ],
      actor: FirestoreHarness.technician,
      note: 'Two more fixtures are out.',
    );
    await pump(app, tester);

    expect(find.text('Material Requests'), findsOneWidget);
    expect(find.text('4 units of LED Bulbs'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();

    final request = await app.read(FirestorePaths.materialRequests, 'rq-1');
    expect(request['status'], 'approved');
    final allocated = await app.data.firestore
        .collection(FirestorePaths.workOrders)
        .doc('w1')
        .collection(FirestorePaths.materialsAllocated)
        .doc('inv-led')
        .get();
    expect(allocated.data()?['quantity'], 4);
    expect(find.text('No request is waiting for review.'), findsOneWidget);
  });

  testWidgets('Scan QR opens the tool whose label was read', (tester) async {
    final app = await console(tester)
      ..nextScan = 'TOOL-TL-0001';
    await pump(app, tester);

    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();

    expect(app.scans, 1);
    expect(find.text('Send to repair'), findsOneWidget);
    expect(find.text('LOANS'), findsOneWidget);
  });

  testWidgets('a tool’s QR label downloads as a PDF', (tester) async {
    final app = await console(tester);
    await pump(app, tester);

    await tester.ensureVisible(find.byTooltip('QR label for TL-0001'));
    await tester.tap(find.byTooltip('QR label for TL-0001'));
    await tester.pumpAndSettle();
    expect(find.text('TOOL-TL-0001'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Download label'));
      // The PDF is laid out off the frame clock.
      for (var i = 0; i < 50 && app.downloads.savedBytes.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();

    final saved = app.downloads.savedBytes.single;
    expect(saved.fileName, 'label-tool-tl-0001.pdf');
    expect(saved.mimeType, 'application/pdf');
    expect(String.fromCharCodes(saved.bytes.take(5)), '%PDF-');
  });
}
