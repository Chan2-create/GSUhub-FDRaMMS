import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/reporting/presentation/report_detail_screen.dart';
import '../../features/reporting/presentation/reports_screen.dart';
import '../../features/work_orders/presentation/task_assignment_screen.dart';
import '../../features/work_orders/presentation/work_orders_screen.dart';
import '../../shells/admin/admin_shell.dart';
import '../../shells/personnel/personnel_shell.dart';
import '../../shells/requestor/requestor_shell.dart';
import 'route_guards.dart';
import 'route_paths.dart';
import 'route_placeholder_screen.dart';

/// Builds the single, path-prefixed [GoRouter] shared by all three shells
/// (`/admin/*`, `/staff/*`, `/personnel/*`).
///
/// [guard] carries the resolved auth state for a router that never changes
/// one — tests, mostly.
///
/// The app passes [guardListenable] instead: one router for the life of the
/// session, re-running `redirect` whenever the signed-in user changes.
/// Rebuilding the router on every auth change disposes the live one, and a
/// browser history event arriving at the disposed instance throws.
GoRouter buildAppRouter({
  AppRouteGuard guard = const AppRouteGuard(),
  ValueListenable<AppRouteGuard>? guardListenable,
  String? initialLocation,
}) => GoRouter(
  initialLocation: initialLocation ?? RoutePaths.adminDashboard,
  refreshListenable: guardListenable,
  redirect: (context, state) =>
      (guardListenable?.value ?? guard).call(context, state),
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
        GoRoute(
          path: RoutePaths.adminReports,
          builder: (context, state) => const ReportsScreen(),
        ),
        GoRoute(
          path: RoutePaths.adminReportDetail,
          builder: (context, state) =>
              ReportDetailScreen(reportId: state.pathParameters['reportId']!),
        ),
        GoRoute(
          path: RoutePaths.adminTaskAssignment,
          builder: (context, state) => TaskAssignmentScreen(
            preselectedReportId: state.uri.queryParameters['report'],
          ),
        ),
        GoRoute(
          path: RoutePaths.adminWorkOrders,
          builder: (context, state) => const WorkOrdersScreen(),
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
  (RoutePaths.adminInventory, 'Inventory Management — Objective 6'),
  (RoutePaths.adminPersonnel, 'Personnel — Objective 2.C'),
  (RoutePaths.adminAnalytics, 'Analytics — Objective 2.C'),
  (RoutePaths.adminUsers, 'User Accounts — Objective 2.C'),
  (RoutePaths.adminMapView, 'Map View — pending confirmation'),
  (RoutePaths.adminNotifications, 'Notifications — later objective'),
  (RoutePaths.adminSettings, 'Settings — later objective'),
];
