import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/routing/app_router.dart';
import 'package:gsuhub/core/routing/route_guards.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/auth_service.dart';

import '../../support/fake_admin_backend.dart';

/// Route table wiring.
///
/// 1.A asserted that each path rendered a placeholder printing its own
/// name. 2.A replaced the placeholders with real screens and put a guard
/// in front of everything, so these now assert on where the router
/// *lands* — the guard's decisions themselves are covered exhaustively in
/// `test/unit/routing/route_guard_test.dart`.
void main() {
  const requestor = AuthUser(
    uid: 'faculty-1',
    email: 'faculty@dorsu.edu.ph',
    role: UserRole.requestor,
  );
  const personnel = AuthUser(
    uid: 'personnel-1',
    email: 'personnel@dorsu.edu.ph',
    role: UserRole.maintenancePersonnel,
  );

  /// Mounts [router] with a backend that answers without Firebase, and
  /// returns the path it settled on.
  Future<String> landingPath(
    WidgetTester tester,
    GoRouter router, {
    AuthUser? user,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1024)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      fakeAdminScope(
        user: user,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    return router.routerDelegate.currentConfiguration.uri.path;
  }

  group('buildAppRouter, signed out', () {
    testWidgets('sends the default landing route to login', (tester) async {
      // `landingPath` defaults to no signed-in user.
      final path = await landingPath(tester, buildAppRouter());

      expect(path, RoutePaths.adminLogin);
    });

    testWidgets('renders the login screen, not a placeholder', (tester) async {
      await landingPath(tester, buildAppRouter());

      expect(find.text('Welcome back!'), findsOneWidget);
    });
  });

  group('buildAppRouter, administrator', () {
    const guard = AppRouteGuard(user: fakeAdminUser);

    testWidgets('lands on the dashboard by default', (tester) async {
      final path = await landingPath(
        tester,
        buildAppRouter(guard: guard),
        user: fakeAdminUser,
      );

      expect(path, RoutePaths.adminDashboard);
    });

    testWidgets('root redirects to the dashboard', (tester) async {
      final path = await landingPath(
        tester,
        buildAppRouter(guard: guard, initialLocation: RoutePaths.root),
        user: fakeAdminUser,
      );

      expect(path, RoutePaths.adminDashboard);
    });

    testWidgets('every sidebar destination resolves inside the shell', (
      tester,
    ) async {
      // Each of these is a real route rather than a 404: the sidebar
      // links to all ten, and one missing entry would be a dead link the
      // guard tests cannot catch.
      for (final path in [
        RoutePaths.adminReports,
        RoutePaths.adminWorkOrders,
        RoutePaths.adminTaskAssignment,
        RoutePaths.adminInventory,
        RoutePaths.adminPersonnel,
        RoutePaths.adminAnalytics,
        RoutePaths.adminUsers,
        RoutePaths.adminMapView,
        RoutePaths.adminNotifications,
        RoutePaths.adminSettings,
      ]) {
        final landed = await landingPath(
          tester,
          buildAppRouter(guard: guard, initialLocation: path),
          user: fakeAdminUser,
        );

        expect(landed, path, reason: '$path did not resolve');
      }
    });
  });

  group('buildAppRouter, mobile shells', () {
    testWidgets('a requestor reaches their own routes', (tester) async {
      final path = await landingPath(
        tester,
        buildAppRouter(
          guard: const AppRouteGuard(user: requestor),
          initialLocation: RoutePaths.staffSubmitReport,
        ),
        user: requestor,
      );

      expect(path, RoutePaths.staffSubmitReport);
    });

    testWidgets('personnel reach their own routes', (tester) async {
      final path = await landingPath(
        tester,
        buildAppRouter(
          guard: const AppRouteGuard(user: personnel),
          initialLocation: RoutePaths.personnelWorkOrders,
        ),
        user: personnel,
      );

      expect(path, RoutePaths.personnelWorkOrders);
    });

    testWidgets('a requestor is bounced out of the admin console', (
      tester,
    ) async {
      final path = await landingPath(
        tester,
        buildAppRouter(
          guard: const AppRouteGuard(user: requestor),
          initialLocation: RoutePaths.adminDashboard,
        ),
        user: requestor,
      );

      expect(path, RoutePaths.staffMyReports);
    });
  });
}
