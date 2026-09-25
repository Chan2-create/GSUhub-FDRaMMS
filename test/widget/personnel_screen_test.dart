import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/personnel_availability.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/user_management/presentation/personnel_screen.dart';

import '../support/fake_admin_backend.dart';

/// Maintenance Personnel (Objective 2.C; Figma `200:4316`).
void main() {
  AppUser staff(
    String id,
    String name, {
    DamageCategory specialization = DamageCategory.electrical,
    int activeTaskCount = 0,
    PersonnelAvailability availability = PersonnelAvailability.available,
    AccountStatus accountStatus = AccountStatus.active,
  }) => AppUser(
    id: id,
    fullName: name,
    email: '$id@dorsu.edu.ph',
    role: UserRole.maintenancePersonnel,
    accountStatus: accountStatus,
    specialization: specialization,
    availability: availability,
    activeTaskCount: activeTaskCount,
    createdAt: DateTime.utc(2026, 9),
    updatedAt: DateTime.utc(2026, 9),
  );

  final roster = [
    staff('p1', 'Marcus Wright', activeTaskCount: 2),
    staff('p2', 'Juan Luna', specialization: DamageCategory.plumbing),
    staff(
      'p3',
      'Pedro Reyes',
      specialization: DamageCategory.carpentry,
      availability: PersonnelAvailability.onLeave,
    ),
    // Deactivated: not part of the working roster.
    staff('p4', 'Carlo Bato', accountStatus: AccountStatus.inactive),
  ];

  Future<FakeUserRepository> pump(
    WidgetTester tester, {
    List<AppUser>? people,
    FakeAccountProvisioningService? provisioning,
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final users = FakeUserRepository(
      personnel: Result.success(people ?? roster),
      signedIn: fakeAdminUser,
    );
    await tester.pumpWidget(
      fakeAdminScope(
        userRepository: users,
        provisioning: provisioning,
        child: const MaterialApp(home: Scaffold(body: PersonnelScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return users;
  }

  group('roster', () {
    testWidgets('counts only active accounts, by live status', (tester) async {
      await pump(tester);

      // Three active: one busy, one available, one on leave.
      Finder card(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is Container),
      );
      expect(
        find.descendant(
          of: card('TOTAL STAFF').first,
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(find.text('Carlo Bato'), findsNothing);
    });

    testWidgets('reads busy from workload and leave from the account', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Busy'), findsOneWidget); // Marcus: 2 active jobs
      expect(find.text('Available'), findsOneWidget); // Juan
      expect(find.text('On leave'), findsOneWidget); // Pedro
    });

    testWidgets('shows each trade as its pill', (tester) async {
      await pump(tester);

      expect(find.text('ELECTRICAL'), findsOneWidget);
      expect(find.text('PLUMBING'), findsOneWidget);
      expect(find.text('CARPENTRY'), findsOneWidget);
    });

    testWidgets('someone on leave cannot be sent to assignment', (
      tester,
    ) async {
      await pump(tester);

      final buttons = tester
          .widgetList<FilledButton>(
            find.widgetWithText(FilledButton, 'Assign Task'),
          )
          .toList();
      expect(buttons, hasLength(3));
      expect(buttons.where((b) => b.onPressed == null), hasLength(1));
    });
  });

  group('filters', () {
    testWidgets('search matches a name or a trade', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'plumb');
      await tester.pumpAndSettle();

      expect(find.text('Juan Luna'), findsOneWidget);
      expect(find.text('Marcus Wright'), findsNothing);
    });

    testWidgets('availability narrows to one status and back', (tester) async {
      await pump(tester);

      await tester.tap(find.text('All Statuses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Busy').last);
      await tester.pumpAndSettle();

      expect(find.text('Marcus Wright'), findsOneWidget);
      expect(find.text('Juan Luna'), findsNothing);

      // The "all" option clears the filter again.
      await tester.tap(find.text('Busy').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Statuses').last);
      await tester.pumpAndSettle();

      expect(find.text('Juan Luna'), findsOneWidget);
    });
  });

  group('adding personnel', () {
    Future<void> fillForm(WidgetTester tester) async {
      await tester.tap(find.text('Add Personnel'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'Rosa Villanueva',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'rosa@dorsu.edu.ph',
      );
      await tester.tap(find.text('Specialization'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Structural').last);
      await tester.pumpAndSettle();
    }

    testWidgets('creates a maintenance account with the chosen trade', (
      tester,
    ) async {
      final provisioning = FakeAccountProvisioningService();
      final users = await pump(tester, provisioning: provisioning);

      await fillForm(tester);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(provisioning.emails, ['rosa@dorsu.edu.ph']);
      final created = users.created.single;
      expect(created.id, 'new-uid');
      expect(created.role, UserRole.maintenancePersonnel);
      expect(created.specialization, DamageCategory.structural);
      expect(
        find.textContaining('A link to set their password'),
        findsOneWidget,
      );
    });

    testWidgets('a refusal stays in the dialog with the input kept', (
      tester,
    ) async {
      final provisioning = FakeAccountProvisioningService(
        refusal: const ValidationFailure(
          'An account already exists for that email address.',
        ),
      );
      final users = await pump(tester, provisioning: provisioning);

      await fillForm(tester);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(
        find.text('An account already exists for that email address.'),
        findsOneWidget,
      );
      expect(find.text('Rosa Villanueva'), findsOneWidget);
      expect(users.created, isEmpty);
    });

    testWidgets('requires a trade before creating', (tester) async {
      final users = await pump(tester);

      await tester.tap(find.text('Add Personnel'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'Rosa Villanueva',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'rosa@dorsu.edu.ph',
      );
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Choose the trade they work in.'), findsOneWidget);
      expect(users.created, isEmpty);
    });
  });

  testWidgets('says so when there is nobody yet', (tester) async {
    await pump(tester, people: const []);

    expect(find.textContaining('No maintenance personnel yet'), findsOneWidget);
  });
}
