import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/routing/route_guards.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/auth_service.dart';

/// Role-based access control (Objective 2.A).
///
/// These matter more than most tests here: the guard is the only thing
/// stopping a requestor who pastes an `/admin/*` URL from reaching the
/// administrator console. Every role is checked against every protected
/// area, plus the unauthenticated and still-resolving cases.
void main() {
  const admin = AuthUser(
    uid: 'admin-1',
    email: 'admin@dorsu.edu.ph',
    role: UserRole.admin,
  );
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

  /// Runs the guard against [location] without needing a live router.
  String? redirectFor(
    AppRouteGuard guard,
    String location, {
    Map<String, String>? query,
  }) {
    final uri = Uri(path: location, queryParameters: query);
    return guard.call(
      _FakeBuildContext(),
      _fakeState(matchedLocation: location, uri: uri),
    );
  }

  group('while the session is still resolving', () {
    const guard = AppRouteGuard(isResolving: true);

    test('holds still rather than bouncing to login', () {
      // Firebase takes a moment to restore a session on browser refresh.
      // Redirecting during that window would sign the user out of their
      // own page on every reload.
      expect(redirectFor(guard, RoutePaths.adminDashboard), isNull);
      expect(redirectFor(guard, RoutePaths.adminReports), isNull);
    });
  });

  group('unauthenticated', () {
    const guard = AppRouteGuard();

    test('is sent to login from an admin route', () {
      final redirect = redirectFor(guard, RoutePaths.adminReports);
      expect(redirect, startsWith(RoutePaths.adminLogin));
    });

    test('keeps the intended destination so sign-in can forward', () {
      final redirect = redirectFor(guard, RoutePaths.adminReports);
      expect(
        Uri.parse(redirect!).queryParameters['redirect'],
        RoutePaths.adminReports,
      );
    });

    test('preserves query parameters on a deep link', () {
      final redirect = redirectFor(
        guard,
        RoutePaths.adminReports,
        query: {'status': 'submitted'},
      );
      final target = Uri.parse(
        Uri.parse(redirect!).queryParameters['redirect']!,
      );
      expect(target.path, RoutePaths.adminReports);
      expect(target.queryParameters['status'], 'submitted');
    });

    test('omits the redirect parameter for the plain dashboard', () {
      // Landing on the default page needs no round-trip bookkeeping.
      final redirect = redirectFor(guard, RoutePaths.adminDashboard);
      expect(Uri.parse(redirect!).queryParameters, isEmpty);
    });

    test('is blocked from the mobile shells too', () {
      // The faculty and staff app has its own sign-in (3.C); personnel
      // have none until Objective 5 and use the administrator's.
      expect(
        redirectFor(guard, RoutePaths.staffMyReports),
        startsWith(RoutePaths.staffLogin),
      );
      expect(
        redirectFor(guard, RoutePaths.personnelDashboard),
        startsWith(RoutePaths.adminLogin),
      );
    });

    test('keeps a faculty deep link through the staff sign-in', () {
      final redirect = redirectFor(guard, RoutePaths.staffMyReports);
      expect(
        Uri.parse(redirect!).queryParameters['redirect'],
        RoutePaths.staffMyReports,
      );
    });

    test('omits the redirect parameter for the faculty home', () {
      // The staff sign-in lands on the home screen by default (3.A).
      final redirect = redirectFor(guard, RoutePaths.staffHome);
      expect(redirect, RoutePaths.staffLogin);
    });

    test('keeps the report form through the staff sign-in', () {
      final redirect = redirectFor(guard, RoutePaths.staffSubmitReport);
      expect(
        Uri.parse(redirect!).queryParameters['redirect'],
        RoutePaths.staffSubmitReport,
      );
    });

    test('may sit on either login page, and on the staff sign-up', () {
      expect(redirectFor(guard, RoutePaths.adminLogin), isNull);
      expect(redirectFor(guard, RoutePaths.staffLogin), isNull);
      // Signing up is how a faculty member gets an account at all (3.A).
      expect(redirectFor(guard, RoutePaths.staffSignUp), isNull);
    });

    test('is sent to the staff sign-in from every faculty tab', () {
      for (final path in [
        RoutePaths.staffHome,
        RoutePaths.staffAlerts,
        RoutePaths.staffProfile,
        RoutePaths.staffReportDetailFor('r1'),
      ]) {
        expect(
          redirectFor(guard, path),
          startsWith(RoutePaths.staffLogin),
          reason: '$path was reachable signed out',
        );
      }
    });
  });

  group('administrator', () {
    const guard = AppRouteGuard(user: admin);

    test('reaches every admin route', () {
      for (final path in [
        RoutePaths.adminDashboard,
        RoutePaths.adminReports,
        RoutePaths.adminWorkOrders,
        RoutePaths.adminInventory,
        RoutePaths.adminPersonnel,
        RoutePaths.adminTaskAssignment,
        RoutePaths.adminAnalytics,
        RoutePaths.adminUsers,
        RoutePaths.adminNotifications,
        RoutePaths.adminSettings,
      ]) {
        expect(redirectFor(guard, path), isNull, reason: 'blocked at $path');
      }
    });

    test('is moved off the login page to the dashboard', () {
      expect(
        redirectFor(guard, RoutePaths.adminLogin),
        RoutePaths.adminDashboard,
      );
    });

    test('is kept out of the faculty and staff app', () {
      // Reports are filed as the signed-in user, and the rules accept them
      // from requestors only (3.C).
      expect(
        redirectFor(guard, RoutePaths.staffSubmitReport),
        RoutePaths.adminDashboard,
      );
    });
  });

  group('requestor', () {
    const guard = AppRouteGuard(user: requestor);

    test('is redirected away from every admin route', () {
      for (final path in [
        RoutePaths.adminDashboard,
        RoutePaths.adminReports,
        RoutePaths.adminUsers,
        RoutePaths.adminSettings,
      ]) {
        expect(
          redirectFor(guard, path),
          RoutePaths.staffHome,
          reason: 'admin route $path was reachable by a requestor',
        );
      }
    });

    test('is sent to their own area, not an error page', () {
      // The brief is explicit: other roles are redirected, not shown an
      // empty admin shell. Their home is the faculty home screen (3.A).
      expect(
        redirectFor(guard, RoutePaths.adminDashboard),
        RoutePaths.staffHome,
      );
    });

    test('is moved off the staff sign-in and sign-up once signed in', () {
      expect(redirectFor(guard, RoutePaths.staffLogin), RoutePaths.staffHome);
      expect(redirectFor(guard, RoutePaths.staffSignUp), RoutePaths.staffHome);
    });

    test('reaches their own shell', () {
      for (final path in [
        RoutePaths.staffHome,
        RoutePaths.staffMyReports,
        RoutePaths.staffReportDetailFor('r1'),
        RoutePaths.staffAlerts,
        RoutePaths.staffProfile,
        RoutePaths.staffSubmitReport,
      ]) {
        expect(redirectFor(guard, path), isNull, reason: 'blocked at $path');
      }
    });
  });

  group('maintenance personnel', () {
    const guard = AppRouteGuard(user: personnel);

    test('is redirected away from every admin route', () {
      for (final path in [
        RoutePaths.adminDashboard,
        RoutePaths.adminReports,
        RoutePaths.adminUsers,
      ]) {
        expect(
          redirectFor(guard, path),
          RoutePaths.personnelDashboard,
          reason: 'admin route $path was reachable by personnel',
        );
      }
    });

    test('reaches their own shell', () {
      expect(redirectFor(guard, RoutePaths.personnelDashboard), isNull);
      expect(redirectFor(guard, RoutePaths.personnelWorkOrders), isNull);
    });

    test('is kept out of the faculty and staff app', () {
      expect(
        redirectFor(guard, RoutePaths.staffSubmitReport),
        RoutePaths.personnelDashboard,
      );
    });
  });

  group('deactivated accounts', () {
    test('never reach the guard as a signed-in user', () {
      // FirebaseAuthService resolves an inactive `users` document to null
      // and signs the session out, so an inactive account arrives here
      // indistinguishable from signed-out — and is bounced to login.
      const guard = AppRouteGuard();
      expect(
        redirectFor(guard, RoutePaths.adminDashboard),
        startsWith(RoutePaths.adminLogin),
      );
    });
  });

  group('redirectTargetOf', () {
    test('reads the forwarding destination off a login route', () {
      final state = _fakeState(
        matchedLocation: RoutePaths.adminLogin,
        uri: Uri(
          path: RoutePaths.adminLogin,
          queryParameters: {'redirect': RoutePaths.adminReports},
        ),
      );
      expect(AppRouteGuard.redirectTargetOf(state), RoutePaths.adminReports);
    });

    test('is null when no destination was recorded', () {
      final state = _fakeState(
        matchedLocation: RoutePaths.adminLogin,
        uri: Uri(path: RoutePaths.adminLogin),
      );
      expect(AppRouteGuard.redirectTargetOf(state), isNull);
    });
  });
}

/// Minimal [GoRouterState] for guard tests.
///
/// The guard only reads `matchedLocation` and `uri`, so building one
/// directly avoids standing up a whole router and widget tree to test a
/// pure function.
GoRouterState _fakeState({required String matchedLocation, required Uri uri}) =>
    GoRouterState(
      _emptyConfiguration,
      uri: uri,
      matchedLocation: matchedLocation,
      fullPath: matchedLocation,
      pathParameters: const {},
      pageKey: ValueKey(matchedLocation),
    );

final _emptyConfiguration = RouteConfiguration(
  ValueNotifier(
    RoutingConfig(
      routes: [GoRoute(path: '/', builder: _stub)],
    ),
  ),
  navigatorKey: GlobalKey<NavigatorState>(),
);

Widget _stub(BuildContext context, GoRouterState state) =>
    const SizedBox.shrink();

/// The guard never touches its context, so a stand-in suffices.
class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
