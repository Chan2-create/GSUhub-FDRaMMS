import 'package:flutter/widgets.dart' show BuildContext;
import 'package:go_router/go_router.dart';

import '../enums/user_role.dart';
import '../services/auth_service.dart';
import 'route_paths.dart';

/// Role-based access control for every navigation in the app.
///
/// 1.A left this as a no-op chokepoint; Objective 2.A turns it into real
/// enforcement. It runs inside `GoRouter.redirect`, which means it applies
/// to **direct URL entry and browser refresh**, not only in-app
/// navigation — the case that matters most on web, where an administrator
/// URL can be pasted by anyone.
///
/// Deliberately a value type holding the resolved auth state rather than
/// reading a provider itself: `GoRouter.redirect` is synchronous, and a
/// guard that had to await a Firestore lookup could not answer in time.
/// `app_router.dart` rebuilds the router when the auth state changes.
class AppRouteGuard {
  const AppRouteGuard({this.user, this.isResolving = false});

  /// The signed-in user, or null when signed out.
  final AuthUser? user;

  /// True while the first auth-state event is still pending.
  ///
  /// Distinct from "signed out": on a browser refresh Firebase takes a
  /// moment to restore the session, and redirecting to login during that
  /// window would sign the user out of their own page on every reload.
  final bool isResolving;

  /// Called by GoRouter before every navigation. Returns a path to
  /// redirect to, or null to allow.
  String? call(BuildContext context, GoRouterState state) {
    final location = state.matchedLocation;
    final isLoginRoute = location == RoutePaths.adminLogin;

    // Hold still until the session is known.
    if (isResolving) return null;

    final signedIn = user != null;

    if (!signedIn) {
      if (isLoginRoute) return null;
      if (!_isProtected(location)) return null;

      // Preserve where they were headed so sign-in can forward them
      // there. Uses the full URI, so query parameters on a deep link
      // survive the round trip.
      final intended = state.uri.toString();
      return Uri(
        path: RoutePaths.adminLogin,
        queryParameters: intended == RoutePaths.adminDashboard
            ? null
            : {_redirectQueryParam: intended},
      ).toString();
    }

    final role = user!.role;

    // A signed-in user sitting on the login page goes to their own home.
    if (isLoginRoute) return _homeFor(role);

    if (_isAdminArea(location) && role != UserRole.admin) {
      // Redirected to their own area rather than shown an empty admin
      // shell: the brief is explicit that other roles are "redirected,
      // not shown an empty shell".
      return _homeFor(role);
    }

    return null;
  }

  /// Query parameter carrying the originally requested location.
  static const String _redirectQueryParam = 'redirect';

  /// Reads the post-login destination off a login route's state.
  static String? redirectTargetOf(GoRouterState state) =>
      state.uri.queryParameters[_redirectQueryParam];

  /// Whether [location] requires authentication at all.
  static bool _isProtected(String location) =>
      _isAdminArea(location) ||
      location.startsWith('/staff') ||
      location.startsWith('/personnel');

  static bool _isAdminArea(String location) => location.startsWith('/admin');

  /// Where each role belongs after signing in.
  ///
  /// The mobile shells are placeholders until Objectives 3 and 5; sending
  /// a requestor or technician there is still correct — they land on their
  /// own area rather than being told they are unauthorized for a system
  /// they are authorized to use.
  static String _homeFor(UserRole role) => switch (role) {
    UserRole.admin => RoutePaths.adminDashboard,
    UserRole.requestor => RoutePaths.staffMyReports,
    UserRole.maintenancePersonnel => RoutePaths.personnelDashboard,
  };
}
