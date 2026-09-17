import 'package:go_router/go_router.dart';

import '../../shells/admin/admin_shell.dart';
import '../../shells/personnel/personnel_shell.dart';
import '../../shells/requestor/requestor_shell.dart';
import 'route_guards.dart';
import 'route_paths.dart';
import 'route_placeholder_screen.dart';

/// Builds the single, path-prefixed [GoRouter] shared by all three shells
/// (`/admin/*`, `/staff/*`, `/personnel/*`) — see
/// docs/architecture_decisions.md "Router structure" for why one router
/// was chosen over three separate entry points. Every screen behind these
/// routes is [RoutePlaceholderScreen] for now — see `route_paths.dart` for
/// which WBS sub-objective owns each one's real UI.
GoRouter buildAppRouter({
  AppRouteGuard guard = const AppRouteGuard(),
}) => GoRouter(
  initialLocation: RoutePaths.adminDashboard,
  redirect: guard.call,
  routes: [
    GoRoute(
      // Placeholder default entry point. Once 2.A implements auth,
      // this should redirect based on the signed-in user's UserRole
      // instead of always landing on the admin shell.
      path: RoutePaths.root,
      redirect: (context, state) => RoutePaths.adminDashboard,
    ),

    // --- Admin (web) — WBS Objective 2 ---
    GoRoute(
      path: RoutePaths.adminLogin,
      builder: (context, state) =>
          const RoutePlaceholderScreen(routeName: RoutePaths.adminLogin),
    ),
    ShellRoute(
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(
          path: RoutePaths.adminDashboard,
          builder: (context, state) => const RoutePlaceholderScreen(
            routeName: RoutePaths.adminDashboard,
          ),
        ),
        GoRoute(
          path: RoutePaths.adminReports,
          builder: (context, state) =>
              const RoutePlaceholderScreen(routeName: RoutePaths.adminReports),
        ),
        GoRoute(
          path: RoutePaths.adminWorkOrders,
          builder: (context, state) => const RoutePlaceholderScreen(
            routeName: RoutePaths.adminWorkOrders,
          ),
        ),
        GoRoute(
          path: RoutePaths.adminUsers,
          builder: (context, state) =>
              const RoutePlaceholderScreen(routeName: RoutePaths.adminUsers),
        ),
        GoRoute(
          path: RoutePaths.adminAnalytics,
          builder: (context, state) => const RoutePlaceholderScreen(
            routeName: RoutePaths.adminAnalytics,
          ),
        ),
      ],
    ),

    // --- Requestor (Faculty/Staff, mobile) — WBS Objective 3 ---
    GoRoute(
      path: RoutePaths.staffLogin,
      builder: (context, state) =>
          const RoutePlaceholderScreen(routeName: RoutePaths.staffLogin),
    ),
    ShellRoute(
      builder: (context, state, child) => RequestorShell(child: child),
      routes: [
        GoRoute(
          path: RoutePaths.staffSubmitReport,
          builder: (context, state) => const RoutePlaceholderScreen(
            routeName: RoutePaths.staffSubmitReport,
          ),
        ),
        GoRoute(
          path: RoutePaths.staffMyReports,
          builder: (context, state) => const RoutePlaceholderScreen(
            routeName: RoutePaths.staffMyReports,
          ),
        ),
        GoRoute(
          path: RoutePaths.staffFeedback,
          builder: (context, state) =>
              const RoutePlaceholderScreen(routeName: RoutePaths.staffFeedback),
        ),
      ],
    ),

    // --- Maintenance Personnel (mobile) — WBS Objective 5 ---
    GoRoute(
      path: RoutePaths.personnelLogin,
      builder: (context, state) =>
          const RoutePlaceholderScreen(routeName: RoutePaths.personnelLogin),
    ),
    ShellRoute(
      builder: (context, state, child) => PersonnelShell(child: child),
      routes: [
        GoRoute(
          path: RoutePaths.personnelDashboard,
          builder: (context, state) => const RoutePlaceholderScreen(
            routeName: RoutePaths.personnelDashboard,
          ),
        ),
        GoRoute(
          path: RoutePaths.personnelWorkOrders,
          builder: (context, state) => const RoutePlaceholderScreen(
            routeName: RoutePaths.personnelWorkOrders,
          ),
        ),
        GoRoute(
          path: RoutePaths.personnelScanning,
          builder: (context, state) => const RoutePlaceholderScreen(
            routeName: RoutePaths.personnelScanning,
          ),
        ),
      ],
    ),
  ],
);
