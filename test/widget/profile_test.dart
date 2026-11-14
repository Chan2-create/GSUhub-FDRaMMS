import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/routing/route_paths.dart';

import '../support/fake_personnel_app.dart';
import '../support/fake_requestor_app.dart';

/// The profile pages (2026-11-13): a header with the person's initials,
/// name and role, then what their account holds in sections. The same
/// cards on the phone, for faculty and staff and for maintenance
/// personnel, and in the console as the administrator's My Profile.
void main() {
  /// Brings [finder] into view in the profile's list.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.dragUntilVisible(
      finder,
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('faculty and staff see who they are and what the account holds', (
    tester,
  ) async {
    final app = RequestorHarness();
    await app.pump(tester, start: RoutePaths.staffProfile);

    // The header: initials, name, email, role and that the account works.
    expect(find.text('MS'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Active account'), findsOneWidget);
    expect(find.text('Faculty / Staff'), findsWidgets);

    // Contact: what is on file, and plainly what is not.
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('College of Engineering'), findsOneWidget);
    expect(find.text('Not on file'), findsOneWidget, reason: 'no number');

    // Theirs is not a maintenance account: no Work section.
    await reveal(tester, find.text('Account'));
    expect(find.text('Work'), findsNothing);
    expect(find.text('January 1, 2026'), findsOneWidget);

    // No Edit button: accounts are changed by the GSU office, and the
    // page says so.
    await reveal(tester, find.widgetWithText(OutlinedButton, 'Logout'));
    expect(find.textContaining('ask the GSU office'), findsOneWidget);
    expect(find.textContaining('Edit'), findsNothing);
  });

  testWidgets('maintenance personnel also see their trade and their load', (
    tester,
  ) async {
    final app = PersonnelHarness();
    await app.data.addPersonnel(fakeTechnician.uid, activeTaskCount: 2);
    await app.pump(tester, start: RoutePaths.personnelProfile);

    expect(find.text('Marcus Wright'), findsOneWidget);
    expect(find.text('Maintenance Personnel'), findsWidgets);

    await reveal(tester, find.text('Work'));
    expect(find.text('Electrical'), findsOneWidget);
    expect(find.text('2 work orders'), findsOneWidget);
  });

  testWidgets(
    'the administrator\'s My Profile shows the same, in the console',
    (tester) async {
      final app = PersonnelHarness(signedIn: fakeAdministrator);
      await app.data.addPersonnel(
        fakeAdministrator.uid,
        role: UserRole.admin,
        fullName: 'Ramon Dela Cruz',
      );
      await app.pump(
        tester,
        start: RoutePaths.adminProfile,
        size: const Size(1536, 900),
      );

      expect(find.text('My Profile'), findsWidgets);
      expect(find.text('Ramon Dela Cruz'), findsOneWidget);
      expect(find.text('GSU Administrator'), findsWidgets);
      expect(find.text('Contact'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      // On a wide window the sections sit beside the header card.
      expect(
        tester.getTopLeft(find.text('Contact')).dx,
        greaterThan(tester.getTopRight(find.text('Ramon Dela Cruz')).dx),
      );
    },
  );
}
