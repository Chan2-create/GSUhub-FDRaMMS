import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/facilities/data/models/facility_draft.dart';

import '../support/fake_firestore_repositories.dart';
import '../support/fake_personnel_app.dart';

/// Facilities & Equipment (Objective 6.C): the rooms and equipment the QR
/// codes name, kept from the console, and their stickers printed.
void main() {
  Future<PersonnelHarness> console(WidgetTester tester) async {
    final app = PersonnelHarness(signedIn: fakeAdministrator);
    await app.data.addPersonnel(fakeAdministrator.uid, role: UserRole.admin);
    await app.data.facilities.createFacility(
      draft: const FacilityDraft(
        buildingName: 'Science Building',
        roomIdentifier: 'Laboratory 1',
        qrCode: 'FAC-SCI-LAB1',
      ),
      actor: FirestoreHarness.admin,
    );
    await app.pump(
      tester,
      start: RoutePaths.adminFacilities,
      size: const Size(1440, 1000),
    );
    return app;
  }

  testWidgets('lists the rooms, and the sidebar leads here', (tester) async {
    await console(tester);

    expect(find.text('Facilities & Equipment'), findsWidgets);
    expect(find.text('Science Building'), findsOneWidget);
    expect(find.text('Laboratory 1'), findsOneWidget);
    expect(find.text('FAC-SCI-LAB1'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
  });

  testWidgets('Add Room registers one with a code from its id', (tester) async {
    final app = await console(tester);

    await tester.tap(find.text('Add Room'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Building'),
      'Engineering Building',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Room (optional)'),
      'Room 305',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add room'));
    await tester.pumpAndSettle();

    final rooms = await app.data.firestore
        .collection(FirestorePaths.facilities)
        .where('roomIdentifier', isEqualTo: 'Room 305')
        .get();
    final room = rooms.docs.single;
    expect(room.data()['qrCode'], 'FAC-${room.id.toUpperCase()}');
    expect(find.text('Room 305'), findsOneWidget);
  });

  testWidgets('a room is deactivated, and left off the report form', (
    tester,
  ) async {
    final app = await console(tester);

    await tester.tap(
      find.byTooltip('Deactivate Science Building, Laboratory 1'),
    );
    await tester.pumpAndSettle();

    expect(find.text('INACTIVE'), findsOneWidget);
    final active = (await app.data.facilities.getFacilities()).fold(
      (rooms) => rooms,
      (f) => fail(f.message),
    );
    expect(active, isEmpty);
  });

  testWidgets('Print all labels saves one sheet for every active room', (
    tester,
  ) async {
    final app = await console(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Print all labels'));
      for (var i = 0; i < 50 && app.downloads.savedBytes.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();

    final sheet = app.downloads.savedBytes.single;
    expect(sheet.fileName, 'gsuhub-room-and-equipment-labels.pdf');
    expect(String.fromCharCodes(sheet.bytes.take(5)), '%PDF-');
    expect(find.textContaining('1 label saved'), findsOneWidget);
  });
}
