import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/routing/app_router.dart';
import 'package:gsuhub/core/routing/route_guards.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/shells/admin/admin_shell.dart';
import 'package:gsuhub/shells/admin/widgets/admin_nav_items.dart';

import '../support/fake_admin_backend.dart';

/// Admin layout chrome (Objective 2.A): sidebar, navigation and sign-out.
void main() {
  late FakeAuthService auth;
  late GoRouter router;

  setUp(() => auth = FakeAuthService(user: fakeAdminUser));

  Future<void> pumpShell(
    WidgetTester tester, {
    String at = RoutePaths.adminDashboard,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    router = buildAppRouter(
      guard: const AppRouteGuard(user: fakeAdminUser),
      initialLocation: at,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      fakeAdminScope(
        authService: auth,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  String currentPath() => router.routerDelegate.currentConfiguration.uri.path;

  group('sidebar', () {
    testWidgets('lists every navigation destination', (tester) async {
      await pumpShell(tester);

      expect(find.text('GSU Administration'), findsOneWidget);
      for (final group in adminNavGroups) {
        expect(
          find.text(group.label),
          findsOneWidget,
          reason: 'group ${group.label} missing',
        );
        for (final item in group.items) {
          expect(
            find.text(item.label),
            findsWidgets,
            reason: 'nav item ${item.label} missing',
          );
        }
      }
    });

    testWidgets('only Dashboard is reachable in 2.A', (tester) async {
      await pumpShell(tester);

      // Every other destination belongs to a later objective. They are
      // shown because the design shows them, disabled because tapping
      // through to an unbuilt screen would be worse than a dead tile.
      final enabled = [
        for (final group in adminNavGroups)
          for (final item in group.items)
            if (item.isEnabled) item.label,
      ];

      expect(enabled, ['Dashboard']);
    });

    testWidgets('a disabled destination does not navigate', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.text('Damage Reports').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(currentPath(), RoutePaths.adminDashboard);
    });

    testWidgets('signs out through the auth service', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();

      // The service call is the assertion, not the resulting route: in the
      // app the router is rebuilt by `appRouterProvider` when auth state
      // changes, whereas this test pins one guard for the whole run.
      expect(auth.signOutCallCount, 1);
    });
  });

  group('top bar', () {
    testWidgets('names the current page once', (tester) async {
      await pumpShell(tester);

      // Figma's leading title slot is an empty frame; filling it as well
      // as the section label printed "Dashboard" twice and overflowed the
      // row. One title, in the sidebar's wording.
      expect(find.text('Dashboard'), findsNWidgets(2)); // sidebar + top bar
    });

    testWidgets('shows deferred actions as disabled with a reason', (
      tester,
    ) async {
      await pumpShell(tester);

      expect(find.text('Export Data'), findsOneWidget);
      expect(find.text('Report New Damage'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Export Data'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Report New Damage'),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('titleFor', () {
    test('names each route from the sidebar definition', () {
      // Derived from `adminNavGroups` so the top bar and the sidebar can
      // never disagree about what a page is called.
      expect(AdminShell.titleFor(RoutePaths.adminDashboard), 'Dashboard');
      expect(AdminShell.titleFor(RoutePaths.adminReports), 'Damage Reports');
    });

    test('falls back rather than showing a bare path', () {
      expect(AdminShell.titleFor('/admin/nothing-here'), 'GSU Administration');
    });
  });
}
