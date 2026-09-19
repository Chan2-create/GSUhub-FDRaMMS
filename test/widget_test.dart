import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/app.dart';
import 'package:gsuhub/core/config/app_config.dart';
import 'package:gsuhub/core/config/env.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/auth_service.dart';

import 'support/fake_admin_backend.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    bool useEmulator = false,
    AuthUser? user = fakeAdminUser,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1024)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      fakeAdminScope(
        user: user,
        useEmulator: useEmulator,
        child: const GsuhubApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a signed-in administrator boots into the dashboard', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Dashboard'), findsWidgets);
  });

  testWidgets('a signed-out visitor boots to login', (tester) async {
    // 1.A booted straight into the admin shell because nothing guarded it.
    // 2.A's guard means an unauthenticated start lands on the login screen
    // instead — the behaviour this test now exists to hold in place.
    await pumpApp(tester, user: null);

    expect(find.text('Welcome back!'), findsOneWidget);
  });

  testWidgets('emulator banner is hidden when not in emulator mode', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.byType(Banner), findsNothing);
  });

  testWidgets('emulator banner is shown in emulator mode', (tester) async {
    await pumpApp(tester, useEmulator: true);

    // The banner is what stops someone mistaking seeded emulator data for
    // the live project during a demo. Its message is painted on a canvas
    // rather than rendered as a Text widget, so assert on the widget.
    final banner = tester.widget<Banner>(find.byType(Banner));
    expect(banner.message, 'EMULATOR');
  });

  test('a development build defaults to the emulators', () {
    // Tests compile without any --dart-define, which is exactly the
    // "developer forgot the flag" case this default exists for: it must
    // land on the emulators, never on the live demo project.
    final config = AppConfig.fromEnvironment();

    expect(config.environment, Environment.development);
    expect(config.useEmulator, isTrue);
    expect(Env.useLiveFirebase, isFalse);
    expect(Env.hasConflictingBackendFlags, isFalse);
    expect(config.appName, 'GSUhub');
  });

  test('RoutePaths keeps each shell on its own prefix', () {
    // The single router relies on these prefixes to tell the three
    // audiences apart; a path that drifted out of its namespace would
    // silently bypass the guard.
    expect(RoutePaths.adminDashboard, startsWith('/admin/'));
    expect(RoutePaths.staffMyReports, startsWith('/staff/'));
    expect(RoutePaths.personnelDashboard, startsWith('/personnel/'));
  });
}
