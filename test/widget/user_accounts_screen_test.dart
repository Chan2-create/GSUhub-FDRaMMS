import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/personnel_availability.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/user_management/presentation/user_accounts_screen.dart';

import '../support/fake_admin_backend.dart';

/// User Accounts (Objective 2.C; Figma `89:4626`).
void main() {
  AppUser account(
    String id,
    String name,
    UserRole role, {
    AccountStatus status = AccountStatus.active,
    String? department,
  }) => AppUser(
    id: id,
    fullName: name,
    email: '$id@dorsu.edu.ph',
    role: role,
    accountStatus: status,
    department: department,
    specialization: role == UserRole.maintenancePersonnel
        ? DamageCategory.electrical
        : null,
    availability: role == UserRole.maintenancePersonnel
        ? PersonnelAvailability.available
        : null,
    createdAt: DateTime.utc(2026, 9, 12),
    updatedAt: DateTime.utc(2026, 9, 12),
  );

  final everyone = [
    // The signed-in administrator (fakeAdminUser's uid).
    account(fakeAdminUser.uid, 'Ramon Dela Cruz', UserRole.admin),
    account('faculty-1', 'Maria Santos', UserRole.requestor, department: 'CAS'),
    account('personnel-1', 'Juan Luna', UserRole.maintenancePersonnel),
    account(
      'personnel-2',
      'Carlo Bato',
      UserRole.maintenancePersonnel,
      status: AccountStatus.inactive,
    ),
  ];

  Future<FakeUserRepository> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1800, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final users = FakeUserRepository(
      personnel: const Result.success([]),
      accounts: Result.success(everyone),
      signedIn: fakeAdminUser,
    );
    await tester.pumpWidget(
      fakeAdminScope(
        userRepository: users,
        child: const MaterialApp(home: Scaffold(body: UserAccountsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return users;
  }

  testWidgets('lists every account with its role and status', (tester) async {
    await pump(tester);

    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('END USER'), findsOneWidget);
    expect(find.text('MAINTENANCE'), findsNWidgets(2));
    expect(find.text('ADMINISTRATOR'), findsOneWidget);
    expect(find.text('INACTIVE'), findsOneWidget);
    expect(find.text('ACTIVE'), findsNWidgets(3));
    // The signed-in account is marked, so nobody edits it by mistake.
    expect(find.text('Ramon Dela Cruz (you)'), findsOneWidget);
    expect(find.text('ROLE LEGEND'), findsOneWidget);
  });

  testWidgets('a tab filters by role and the select follows it', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('End Users'));
    await tester.pumpAndSettle();

    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Juan Luna'), findsNothing);
    // One filter drawn twice: the select now names the same role.
    expect(find.text('End User'), findsWidgets);
    expect(find.text('All Roles'), findsNothing);
  });

  testWidgets('search matches a name or an email', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'personnel-2@');
    await tester.pumpAndSettle();

    expect(find.text('Carlo Bato'), findsOneWidget);
    expect(find.text('Juan Luna'), findsNothing);
  });

  group('row menu', () {
    Future<void> openMenuFor(WidgetTester tester, String name) async {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: row.first, matching: find.byIcon(Icons.more_vert)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('deactivating asks first, then records the change', (
      tester,
    ) async {
      final users = await pump(tester);

      await openMenuFor(tester, 'Juan Luna');
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(find.text('Deactivate Juan Luna?'), findsOneWidget);
      expect(users.statusChanges, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await tester.pumpAndSettle();

      expect(users.statusChanges.single.uid, 'personnel-1');
      expect(users.statusChanges.single.status, AccountStatus.inactive);
      expect(find.text('Deactivated Juan Luna.'), findsOneWidget);
    });

    testWidgets('an inactive account can be reactivated', (tester) async {
      final users = await pump(tester);

      await openMenuFor(tester, 'Carlo Bato');
      await tester.tap(find.text('Reactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reactivate'));
      await tester.pumpAndSettle();

      expect(users.statusChanges.single.status, AccountStatus.active);
    });

    testWidgets('your own account cannot be deactivated', (tester) async {
      final users = await pump(tester);

      await openMenuFor(tester, 'Ramon Dela Cruz (you)');
      final item = tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text('Deactivate'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );

      expect(item.enabled, isFalse);
      expect(users.statusChanges, isEmpty);
    });

    testWidgets('editing saves the changed details', (tester) async {
      final users = await pump(tester);

      await openMenuFor(tester, 'Maria Santos');
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Department (optional)'),
        'Registrar\'s Office',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(users.updated.single.department, "Registrar's Office");
      expect(users.updated.single.email, 'faculty-1@dorsu.edu.ph');
      expect(find.text('Saved changes to Maria Santos.'), findsOneWidget);
    });

    testWidgets('your own role is locked in the edit form', (tester) async {
      await pump(tester);

      await openMenuFor(tester, 'Ramon Dela Cruz (you)');
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('cannot change your own role'),
        findsOneWidget,
      );
    });
  });
}
