import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../shells/admin/admin_shell.dart';
import '../../shells/personnel/personnel_shell.dart';
import '../../shells/requestor/requestor_shell.dart';
import 'route_guards.dart';
import 'route_paths.dart';
import 'route_placeholder_screen.dart';

/// Builds the single, path-prefixed [GoRouter] shared by all three shells
/// (`/admin/*`, `/staff/*`, `/personnel/*`).
///
/// [guard] carries the resolved auth state; `app.dart` rebuilds the router
/// when that state changes so `redirect` always evaluates against a
/// current session.
GoRouter buildAppRouter({
  AppRouteGuard guard = const AppRouteGuard(),
  String? initialLocation,
}) => GoRouter(
  initialLocation: initialLocation ?? RoutePaths.adminDashboard,
  redirect: guard.call,
  routes: [
    GoRoute(
      path: RoutePaths.root,
      redirect: (context, state) => RoutePaths.adminDashboard,
    ),

    // --- Admin (web) — WBS Objective 2 ---
    GoRoute(
      path: RoutePaths.adminLogin,
      builder: (context, state) =>
          LoginScreen(redirectTo: AppRouteGuard.redirectTargetOf(state)),
    ),
    ShellRoute(
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(
          path: RoutePaths.adminDashboard,
          builder: (context, state) => const DashboardScreen(),
        ),
        // Reachable by URL but not from the sidebar, which disables them.
        // Each names the objective that will build it.
        for (final placeholder in _adminPlaceholders)
          GoRoute(
            path: placeholder.$1,
            builder: (context, state) =>
                RoutePlaceholderScreen(routeName: placeholder.$2),
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

/// Admin routes whose screens belong to later objectives. Kept as a list
/// so adding one is a single line rather than a copied `GoRoute` block.
const List<(String, String)> _adminPlaceholders = [
  (RoutePaths.adminReports, 'Damage Reports — Objective 2.B'),
  (RoutePaths.adminWorkOrders, 'Work Orders — Objective 2.B'),
  (RoutePaths.adminTaskAssignment, 'Task Assignment — Objective 2.B'),
  (RoutePaths.adminInventory, 'Inventory Management — Objective 6'),
  (RoutePaths.adminPersonnel, 'Personnel — Objective 2.C'),
  (RoutePaths.adminAnalytics, 'Analytics — Objective 2.C'),
  (RoutePaths.adminUsers, 'User Accounts — Objective 2.C'),
  (RoutePaths.adminMapView, 'Map View — pending confirmation'),
  (RoutePaths.adminNotifications, 'Notifications — later objective'),
  (RoutePaths.adminSettings, 'Settings — later objective'),
];
