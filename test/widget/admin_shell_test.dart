import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/routing/app_router.dart';
import 'package:gsuhub/core/routing/route_guards.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/shells/admin/admin_shell.dart';
import 'package:gsuhub/shells/admin/widgets/admin_nav_items.dart';
import 'package:gsuhub/shells/admin/widgets/admin_sidebar.dart';
import 'package:gsuhub/shells/admin/widgets/admin_top_bar.dart';

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
    testWidgets('reaches screen readers, not only the page beside it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpShell(tester, at: RoutePaths.adminReports);

      // Each page's route draws a modal barrier, which drops from the
      // semantics tree everything painted before it in the same container.
      // Without a container of the page area's own, that was the whole
      // shell: sidebar and top bar went unread (found during 4.C).
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      expect(find.bySemanticsLabel('GSU Administration'), findsOneWidget);
      semantics.dispose();
    });

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

    testWidgets('exposes exactly the destinations built so far', (
      tester,
    ) async {
      await pumpShell(tester);

      // Every destination is built: Map View, the last, on 2026-11-12,
      // scoped to what the manuscript says geo-tags are for.
      final enabled = [
        for (final group in adminNavGroups)
          for (final item in group.items)
            if (item.isEnabled) item.label,
      ];

      expect(enabled, [
        'Dashboard', // 2.A
        'Damage Reports', // 2.B
        'Inventory Management', // 6.A
        'Personnel', // 2.C
        'Task Assignment', // 2.B
        'Work Order Management', // 2.B
        'Map View', // geo-tagged reports, 2026-11-12
        'Analytics', // 2.C
        'User Accounts', // 2.C
        'Facilities & Equipment', // 6.C
        'Notifications', // 7.A
        'Settings', // 4.A
      ]);
    });

    testWidgets('carries Work Order Management, added from node 202:5355', (
      tester,
    ) async {
      await pumpShell(tester);

      // The 2.A sidebar (node 196:534) has no such item, so the screen
      // would otherwise have no way in. The one deliberate deviation.
      expect(find.text('Work Order Management'), findsWidgets);
    });

    testWidgets('Map View opens from the sidebar', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.text('Map View').first);
      await tester.pumpAndSettle();

      expect(currentPath(), RoutePaths.adminMapView);
      // The fixture's reports carry no geo-tag, so the page says so
      // rather than drawing an empty map.
      expect(
        find.text('No open report has a geo-tag to show.'),
        findsOneWidget,
      );
    });

    testWidgets('no longer carries Logout: it is in the account menu', (
      tester,
    ) async {
      await pumpShell(tester);

      expect(find.byTooltip('Sign out'), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
    });
  });

  // The header's gold circle (2026-11-13): who is signed in, My Profile
  // and Logout, which asks first.
  group('account menu', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens under the gold circle, with who is signed in', (
      tester,
    ) async {
      await pumpShell(tester);
      await openMenu(tester);

      expect(find.text(fakeAdminUser.email), findsOneWidget);
      expect(find.text('GSU Administrator'), findsOneWidget);
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
      // Below the circle, not over it.
      expect(
        tester.getTopLeft(find.text('My Profile')).dy,
        greaterThan(tester.getBottomLeft(find.byTooltip('Account')).dy),
      );
    });

    testWidgets('Logout asks first, then signs out through the auth service', (
      tester,
    ) async {
      await pumpShell(tester);
      await openMenu(tester);
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      expect(find.text('Log out of GSUhub?'), findsOneWidget);
      expect(auth.signOutCallCount, 0, reason: 'not before it is confirmed');
      await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
      await tester.pumpAndSettle();

      // The service call is the assertion, not the resulting route: in the
      // app the router is rebuilt by `appRouterProvider` when auth state
      // changes, whereas this test pins one guard for the whole run.
      expect(auth.signOutCallCount, 1);
    });

    testWidgets('Cancel keeps the session', (tester) async {
      await pumpShell(tester);
      await openMenu(tester);
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(auth.signOutCallCount, 0);
      expect(currentPath(), RoutePaths.adminDashboard);
    });

    testWidgets('My Profile opens the administrator\'s own account', (
      tester,
    ) async {
      await pumpShell(tester);
      await openMenu(tester);
      await tester.tap(find.text('My Profile'));
      await tester.pumpAndSettle();

      expect(currentPath(), RoutePaths.adminProfile);
      // Named in the header, though the sidebar has no entry for it.
      expect(AdminShell.titleFor(RoutePaths.adminProfile), 'My Profile');
    });

    testWidgets('is in the phone\'s bar too, where the sidebar is a drawer', (
      tester,
    ) async {
      await pumpShell(tester);
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();

      await openMenu(tester);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('is drawn once at every width', (tester) async {
      await pumpShell(tester);
      // A phone's bar, a tablet's narrow card, a laptop's full card: the
      // tablet once showed two gold circles, one in the card and one
      // beside it.
      for (final width in [360.0, 800.0, 1100.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Account'),
          findsOneWidget,
          reason: 'at $width wide',
        );
      }
    });
  });

  group('top bar', () {
    testWidgets('runs the full width, the logo over the sidebar, as drawn', (
      tester,
    ) async {
      await pumpShell(tester);

      final bar = tester.getRect(find.byType(AdminTopBar));
      expect(bar.width, 1440);
      expect(bar.height, AdminTopBar.height);
      expect(find.bySemanticsLabel('GSUhub'), findsOneWidget);
      // The 13px gold rule sits between the header and the sidebar.
      expect(tester.getRect(find.byType(AdminSidebar)).top, bar.bottom + 13);
    });

    testWidgets('names the current page once', (tester) async {
      await pumpShell(tester);

      // Figma's leading title slot is an empty frame; filling it as well
      // as the section label printed "Dashboard" twice and overflowed the
      // row. One title, in the sidebar's wording.
      expect(find.text('Dashboard'), findsNWidgets(2)); // sidebar + top bar
    });

    testWidgets(
      'offers Export Data, and explains the admin cannot file reports',
      (tester) async {
        await pumpShell(tester);

        expect(find.text('Export Data'), findsOneWidget);
        expect(find.text('Report New Damage'), findsOneWidget);
        // 2.C: the export works from every page.
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Export Data'),
              )
              .onPressed,
          isNotNull,
        );
        // Filing a report is a faculty/staff function, from the mobile app.
        expect(
          find.byTooltip(
            'Reports are submitted by faculty and staff from the mobile app — '
            'not from the admin console.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Report New Damage'),
              )
              .onPressed,
          isNull,
        );
      },
    );
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
