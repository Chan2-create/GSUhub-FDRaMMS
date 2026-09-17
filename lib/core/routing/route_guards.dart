import 'package:flutter/widgets.dart' show BuildContext;
import 'package:go_router/go_router.dart';

/// Route-guard SCAFFOLDING ONLY.
///
/// [call] is wired into [GoRouter.redirect] so every navigation — across
/// all three shells — already passes through a single, well-known
/// chokepoint, but it always returns `null` (never redirects) for now.
/// Real authentication-state and role-based access checks (is this user
/// signed in? does their [UserRole] match the `/admin`, `/staff`, or
/// `/personnel` prefix they're navigating into?) are Objective 2.A's
/// responsibility, built against `core/services/auth_service.dart`.
///
/// Deliberately a callable class rather than a bare function so 2.A can
/// inject an [AuthService] (see `../services/auth_service.dart`) without
/// changing `app_router.dart`'s call site.
class AppRouteGuard {
  const AppRouteGuard();

  /// Called by GoRouter before every navigation. Returning `null` allows
  /// the navigation to proceed unmodified; returning a path string
  /// redirects to it instead.
  ///
  /// TODO(2.A): read [AuthService.currentUser] here. Unauthenticated users
  /// should redirect to the login route matching the shell they're
  /// entering; authenticated users whose [UserRole] doesn't match the
  /// shell's prefix should be denied.
  String? call(BuildContext context, GoRouterState state) => null;
}
