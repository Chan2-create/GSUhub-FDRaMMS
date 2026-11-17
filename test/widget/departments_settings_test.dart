import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/features/settings/presentation/settings_screen.dart';

import '../support/app_fonts.dart';
import '../support/fake_admin_backend.dart';
import '../support/fake_departments.dart';

/// Settings → Departments (2026-11-17): the list Create Account offers,
/// kept by the administrator, a change at a time.
void main() {
  setUpAll(loadAppFonts);

  Future<FakeDepartmentRepository> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 1600),
    FakeDepartmentRepository? departments,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository =
        departments ??
        FakeDepartmentRepository(FakeDepartmentRepository.sample());
    await tester.pumpWidget(
      fakeAdminScope(
        departments: repository,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Departments').first);
    await tester.tap(find.text('Departments').first);
    await tester.pumpAndSettle();
    return repository;
  }

  Finder rowButton(String department, String label) => find.descendant(
    of: find.ancestor(
      of: find.textContaining(department),
      matching: find.byType(Wrap),
    ),
    matching: find.widgetWithText(TextButton, label),
  );

  testWidgets('lists every department, the retired ones marked', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Departments and faculties'), findsOneWidget);
    for (final name in [
      'Faculty of Business and Management',
      'Faculty of Computing, Engineering and Technology',
      'General Services Unit',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Old Office  · retired'), findsOneWidget);
    expect(find.textContaining('· retired'), findsOneWidget);
    expect(rowButton('Old Office', 'Restore'), findsOneWidget);
    expect(rowButton('General Services Unit', 'Retire'), findsOneWidget);
  });

  testWidgets('adds one, and says so', (tester) async {
    final departments = await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('new-department')),
      'Faculty of Nursing and Allied Health Sciences',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(
      departments.all.map((d) => d.name),
      contains('Faculty of Nursing and Allied Health Sciences'),
    );
    expect(
      find.text('Added Faculty of Nursing and Allied Health Sciences.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Faculty of Nursing and Allied Health Sciences'),
      findsWidgets,
      reason: 'on the list at once',
    );
  });

  testWidgets('a name already on the list is refused, whatever the case', (
    tester,
  ) async {
    final departments = await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('new-department')),
      'general services unit',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(
      find.text('General Services Unit is already on the list.'),
      findsOneWidget,
    );
    expect(departments.all, hasLength(4));
  });

  testWidgets('renames one', (tester) async {
    final departments = await pump(tester);

    await tester.tap(rowButton('General Services Unit', 'Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'General Services Office',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(
      departments.all.map((d) => d.name),
      contains('General Services Office'),
    );
    expect(find.text('Renamed to General Services Office.'), findsOneWidget);
  });

  testWidgets('retires one, and restores it', (tester) async {
    final departments = await pump(tester);

    await tester.tap(rowButton('General Services Unit', 'Retire'));
    await tester.pumpAndSettle();
    expect(
      departments.all.firstWhere((d) => d.id == 'dep-gsu').isActive,
      isFalse,
    );
    expect(find.text('Retired General Services Unit.'), findsOneWidget);

    await tester.tap(rowButton('General Services Unit', 'Restore'));
    await tester.pumpAndSettle();
    expect(
      departments.all.firstWhere((d) => d.id == 'dep-gsu').isActive,
      isTrue,
    );
  });

  testWidgets('fits a phone', (tester) async {
    await pump(tester, size: const Size(320, 1600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty list says what that means for sign-up', (tester) async {
    await pump(tester, departments: FakeDepartmentRepository());

    expect(
      find.text(
        'No departments yet. Until there are, faculty and staff create '
        'accounts without one.',
      ),
      findsOneWidget,
    );
  });
}
