import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/facilities/data/models/facility_draft.dart';

import '../support/fake_firestore_repositories.dart';
import '../support/fake_personnel_app.dart';

/// Delete and archive from the console's lists (2026-11-08), over the
/// in-memory backend: each asks first and names what goes, a refusal is
/// shown in the dialog, success is announced, and the list updates at
/// once. What the database refuses is proven in
/// supabase/tests/console_delete_archive.test.sql.
void main() {
  Future<PersonnelHarness> console() async {
    final app = PersonnelHarness(signedIn: fakeAdministrator);
    await app.data.addPersonnel(
      fakeAdministrator.uid,
      role: UserRole.admin,
      fullName: 'Ramon Dela Cruz',
    );
    return app;
  }

  Future<void> open(PersonnelHarness app, WidgetTester tester, String path) =>
      app.pump(tester, start: path, size: const Size(1440, 1400));

  Future<void> confirm(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  group('tools', () {
    testWidgets('a tool is deleted from its row, after naming it', (
      tester,
    ) async {
      final app = await console();
      await app.data.addTool('tool-1');
      await open(app, tester, RoutePaths.adminInventory);

      await tester.ensureVisible(find.byTooltip('Delete Fluke Multimeter'));
      await tester.tap(find.byTooltip('Delete Fluke Multimeter'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Fluke Multimeter (TL-0001)?'), findsOneWidget);
      await confirm(tester, 'Delete');

      final tool = await app.read(FirestorePaths.tools, 'tool-1');
      expect(tool['deletedAt'], isNotNull);
      expect(find.text('Deleted Fluke Multimeter.'), findsOneWidget);
      expect(find.text('TL-0001'), findsNothing);
      final audit = await app.data.auditEntries();
      expect(
        audit.map((entry) => entry['description']),
        contains('Deleted Fluke Multimeter (TL-0001) from the tools'),
      );
    });

    testWidgets('a tool out on loan is kept, and the dialog says why', (
      tester,
    ) async {
      final app = await console();
      await app.data.addTool('tool-1', status: ToolStatus.borrowed);
      await open(app, tester, RoutePaths.adminInventory);

      await tester.ensureVisible(find.byTooltip('Delete Fluke Multimeter'));
      await tester.tap(find.byTooltip('Delete Fluke Multimeter'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Delete');

      expect(
        find.text('Fluke Multimeter is on loan. Check it in first.'),
        findsOneWidget,
      );
      expect(find.text('Delete Fluke Multimeter (TL-0001)?'), findsOneWidget);
      expect(
        (await app.read(FirestorePaths.tools, 'tool-1'))['deletedAt'],
        isNull,
      );
    });

    testWidgets('a material is deleted from the corner of its card', (
      tester,
    ) async {
      final app = await console();
      await app.data.addInventoryItem('inv-led');
      await open(app, tester, RoutePaths.adminInventory);

      await tester.tap(find.byTooltip('Delete LED Bulbs'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Delete');

      expect(
        (await app.read(FirestorePaths.inventoryItems, 'inv-led'))['deletedAt'],
        isNotNull,
      );
      expect(find.text('LED Bulbs'), findsNothing);
    });
  });

  testWidgets('a room with equipment is kept; the equipment, then the room, '
      'are deleted', (tester) async {
    final app = await console();
    final room = await app.data.facilities.createFacility(
      draft: const FacilityDraft(
        buildingName: 'Science Building',
        roomIdentifier: 'Laboratory 1',
        qrCode: 'FAC-SCI-LAB1',
      ),
      actor: FirestoreHarness.admin,
    );
    final roomId = room.fold((id) => id, (_) => '');
    await app.data.facilities.createAsset(
      draft: AssetDraft(
        name: 'Fume Hood',
        facilityId: roomId,
        condition: ItemCondition.good,
      ),
      actor: FirestoreHarness.admin,
    );
    await open(app, tester, RoutePaths.adminFacilities);

    await tester.tap(find.byTooltip('Delete Science Building, Laboratory 1'));
    await tester.pumpAndSettle();
    await confirm(tester, 'Delete');
    expect(
      find.text(
        'Science Building, Laboratory 1 still has 1 piece of equipment. '
        'Delete it or move it to another room first.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete Fume Hood'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Fume Hood?'), findsOneWidget);
    await confirm(tester, 'Delete');
    expect(find.text('Deleted Fume Hood.'), findsOneWidget);
    expect(find.text('Fume Hood'), findsNothing);

    await tester.tap(find.byTooltip('Delete Science Building, Laboratory 1'));
    await tester.pumpAndSettle();
    await confirm(tester, 'Delete');
    expect(
      (await app.read(FirestorePaths.facilities, roomId))['deletedAt'],
      isNotNull,
    );
    expect(find.text('Laboratory 1'), findsNothing);
  });

  testWidgets('deleting the only active room warns that no report can then '
      'be filed', (tester) async {
    // A report needs a registered room. On the live system the last one
    // was deleted, and the report form's Building and Room went dead
    // (2026-11-13).
    final app = await console();
    Future<void> addRoom(String room, String code) =>
        app.data.facilities.createFacility(
          draft: FacilityDraft(
            buildingName: 'Science Building',
            roomIdentifier: room,
            qrCode: code,
          ),
          actor: FirestoreHarness.admin,
        );
    await addRoom('Laboratory 1', 'FAC-SCI-LAB1');
    await open(app, tester, RoutePaths.adminFacilities);

    const warning =
        'This is the only active room. Until another is added, faculty and '
        'staff cannot file a report.';
    await tester.tap(find.byTooltip('Delete Science Building, Laboratory 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining(warning), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // With a second room, deleting one is nothing to warn about.
    await addRoom('Laboratory 2', 'FAC-SCI-LAB2');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete Science Building, Laboratory 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining(warning), findsNothing);
  });

  group('accounts', () {
    Future<void> openMenu(WidgetTester tester, String name) async {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(
          of: row.first,
          matching: find.byTooltip('Account actions'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a sign-up with no records is deleted', (tester) async {
      final app = await console();
      await app.data.addPersonnel(
        'pending-1',
        role: UserRole.requestor,
        accountStatus: AccountStatus.pending,
        fullName: 'Liza Tan',
      );
      await open(app, tester, RoutePaths.adminUsers);

      await openMenu(tester, 'Liza Tan');
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete the account of Liza Tan?'), findsOneWidget);
      await confirm(tester, 'Delete');

      expect(await app.read(FirestorePaths.users, 'pending-1'), isEmpty);
      expect(find.text('Deleted the account of Liza Tan.'), findsOneWidget);
      expect(find.text('Liza Tan'), findsNothing);
    });

    testWidgets('an account with records is kept, to be deactivated', (
      tester,
    ) async {
      final app = await console();
      await app.data.addPersonnel(
        'faculty-1',
        role: UserRole.requestor,
        fullName: 'Maria Santos',
      );
      // The fixture report is Maria Santos's (reporter faculty-1).
      await app.data.addReport('rep-1');
      await open(app, tester, RoutePaths.adminUsers);

      await openMenu(tester, 'Maria Santos');
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Delete');

      expect(
        find.text(
          'Maria Santos has records in GSUhub (reports, work or history), so '
          'the account stays to keep them. Deactivate it instead.',
        ),
        findsOneWidget,
      );
      expect(await app.read(FirestorePaths.users, 'faculty-1'), isNotEmpty);
    });

    testWidgets('your own account cannot be deleted', (tester) async {
      final app = await console();
      await open(app, tester, RoutePaths.adminUsers);

      await openMenu(tester, 'Ramon Dela Cruz (you)');
      final item = tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text('Delete account'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      expect(item.enabled, isFalse);
    });
  });

  testWidgets('a closed report is archived, found in the archive, and '
      'restored', (tester) async {
    final app = await console();
    await app.data.addReport('rep-1', status: ReportStatus.closed);
    await app.data.addReport('rep-2', status: ReportStatus.submitted);
    await open(app, tester, RoutePaths.adminReports);

    // An open report cannot be archived.
    expect(
      find.byTooltip(
        'Only a closed, merged or rejected report can be archived.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Archive this report'));
    await tester.pumpAndSettle();
    expect(find.text('Archive report #REP-1?'), findsOneWidget);
    await confirm(tester, 'Archive');

    expect(
      (await app.read(FirestorePaths.damageReports, 'rep-1'))['archivedAt'],
      isNotNull,
    );
    expect(
      (await app.read(FirestorePaths.damageReports, 'rep-1'))['status'],
      ReportStatus.closed.id,
    );
    expect(find.text('Archived report #REP-1.'), findsOneWidget);
    expect(find.text('#REP-1'), findsNothing);
    expect(find.text('#REP-2'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Archived'));
    await tester.pumpAndSettle();
    expect(find.text('#REP-1'), findsOneWidget);
    expect(find.text('#REP-2'), findsNothing);

    await tester.tap(find.byTooltip('Restore this report to the list'));
    await tester.pumpAndSettle();
    await confirm(tester, 'Restore');
    expect(
      (await app.read(FirestorePaths.damageReports, 'rep-1'))['archivedAt'],
      isNull,
    );
    expect(find.text('#REP-1'), findsNothing, reason: 'out of the archive');
  });

  testWidgets('a completed work order is archived from the board', (
    tester,
  ) async {
    final app = await console();
    await app.data.addPersonnel(fakeTechnician.uid);
    await app.data.addReport(
      'rep-1',
      status: ReportStatus.completed,
      workOrderId: 'wo-1',
    );
    await app.data.addWorkOrder(
      'wo-1',
      reportIds: ['rep-1'],
      status: WorkOrderStatus.completed,
    );
    // Finished today, inside the board's default "Last 30 Days".
    await app.data.firestore
        .collection(FirestorePaths.workOrders)
        .doc('wo-1')
        .update({'completedAt': Timestamp.now()});
    await open(app, tester, RoutePaths.adminWorkOrders);

    expect(find.text('Flickering lights'), findsOneWidget);
    // The board scrolls sideways to its Completed column.
    await tester.ensureVisible(find.byTooltip('Work order actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Work order actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Archive work order #WO-1?'), findsOneWidget);
    await confirm(tester, 'Archive');

    expect(
      (await app.read(FirestorePaths.workOrders, 'wo-1'))['archivedAt'],
      isNotNull,
    );
    expect(find.text('Flickering lights'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Archived'));
    await tester.pumpAndSettle();
    expect(find.text('Flickering lights'), findsOneWidget);
  });
}
