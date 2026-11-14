import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/accomplishment/presentation/personnel_materials_screen.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/auth/presentation/admin_login_screen.dart';
import '../../features/auth/presentation/mobile_login_screen.dart';
import '../../features/auth/presentation/requestor_sign_up_screen.dart';
import '../../features/damage_reports/presentation/my_reports/my_report_detail_screen.dart';
import '../../features/damage_reports/presentation/my_reports/my_reports_screen.dart';
import '../../features/damage_reports/presentation/report_detail_screen.dart';
import '../../features/damage_reports/presentation/reports_screen.dart';
import '../../features/damage_reports/presentation/submission/submit_report_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/dashboard/presentation/personnel_home_screen.dart';
import '../../features/dashboard/presentation/requestor_home_screen.dart';
import '../../features/facilities/presentation/facilities_screen.dart';
import '../../features/feedback/presentation/rate_service_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/inventory/presentation/personnel/material_request_screen.dart';
import '../../features/map_view/presentation/report_map_screen.dart';
import '../../features/notifications/presentation/admin_notifications_screen.dart';
import '../../features/notifications/presentation/mobile_alerts_screen.dart';
import '../../features/qr_codes/presentation/scan_result_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/tasks/presentation/personnel_tasks_screen.dart';
import '../../features/user_management/presentation/admin_profile_screen.dart';
import '../../features/user_management/presentation/mobile_profile_screen.dart';
import '../../features/user_management/presentation/personnel_screen.dart';
import '../../features/user_management/presentation/user_accounts_screen.dart';
import '../../features/work_orders/presentation/personnel/my_work_orders_screen.dart';
import '../../features/work_orders/presentation/personnel/personnel_work_order_screen.dart';
import '../../features/work_orders/presentation/task_assignment_screen.dart';
import '../../features/work_orders/presentation/work_order_detail_screen.dart';
import '../../features/work_orders/presentation/work_orders_screen.dart';
import '../../shells/admin/admin_shell.dart';
import '../../shells/personnel/personnel_shell.dart';
import '../../shells/requestor/requestor_shell.dart';
import 'route_guards.dart';
import 'route_paths.dart';

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
          AdminLoginScreen(redirectTo: AppRouteGuard.redirectTargetOf(state)),
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
          routes: [
            GoRoute(
              path: ':workOrderId',
              builder: (context, state) => WorkOrderDetailScreen(
                workOrderId: state.pathParameters['workOrderId']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: RoutePaths.adminInventory,
          builder: (context, state) => const InventoryScreen(),
        ),
        GoRoute(
          path: RoutePaths.adminFacilities,
          builder: (context, state) => const FacilitiesScreen(),
        ),
        GoRoute(
          path: RoutePaths.adminPersonnel,
          builder: (context, state) => const PersonnelScreen(),
        ),
        GoRoute(
          path: RoutePaths.adminAnalytics,
          builder: (context, state) => const AnalyticsScreen(),
        ),
        GoRoute(
          path: RoutePaths.adminUsers,
          builder: (context, state) => const UserAccountsScreen(),
        ),
        GoRoute(
          path: RoutePaths.adminSettings,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: RoutePaths.adminNotifications,
          builder: (context, state) => const AdminNotificationsScreen(),
        ),
        // The administrator's own account, from the header's menu.
        GoRoute(
          path: RoutePaths.adminProfile,
          builder: (context, state) => const AdminProfileScreen(),
        ),
        // Geo-tagged reports on the campus map (2026-11-12).
        GoRoute(
          path: RoutePaths.adminMapView,
          builder: (context, state) => const ReportMapScreen(),
        ),
      ],
    ),

    // --- Requestor (Faculty/Staff, mobile) — WBS Objective 3 ---
    GoRoute(
      path: RoutePaths.staffLogin,
      builder: (context, state) => MobileLoginScreen(
        redirectTo: AppRouteGuard.redirectTargetOf(state),
        justRegistered:
            state.uri.queryParameters[MobileLoginScreen.registeredParam] == '1',
      ),
    ),
    GoRoute(
      path: RoutePaths.staffSignUp,
      builder: (context, state) => const RequestorSignUpScreen(),
    ),
    // Over the tabs, not inside them: the form's frame has no bottom bar,
    // and the bar's centre button opens it with `push` so Back returns.
    GoRoute(
      path: RoutePaths.staffSubmitReport,
      builder: (context, state) => const SubmitReportScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) =>
          RequestorShell(location: state.matchedLocation, child: child),
      routes: [
        GoRoute(
          path: RoutePaths.staffHome,
          builder: (context, state) => const RequestorHomeScreen(),
        ),
        GoRoute(
          path: RoutePaths.staffMyReports,
          builder: (context, state) => const MyReportsScreen(),
          routes: [
            GoRoute(
              path: ':reportId',
              builder: (context, state) => MyReportDetailScreen(
                reportId: state.pathParameters['reportId']!,
              ),
              routes: [
                GoRoute(
                  path: 'rate',
                  builder: (context, state) => RateServiceScreen(
                    reportId: state.pathParameters['reportId']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: RoutePaths.staffAlerts,
          builder: (context, state) => const MobileAlertsScreen(),
        ),
        GoRoute(
          path: RoutePaths.staffProfile,
          builder: (context, state) => const MobileProfileScreen(),
        ),
      ],
    ),

    // --- Maintenance Personnel (mobile) — WBS Objective 5 ---
    // Signed in on the mobile app's one sign-in page (staffLogin).
    ShellRoute(
      builder: (context, state, child) =>
          PersonnelShell(location: state.matchedLocation, child: child),
      routes: [
        GoRoute(
          path: RoutePaths.personnelDashboard,
          builder: (context, state) => const PersonnelHomeScreen(),
        ),
        GoRoute(
          path: RoutePaths.personnelTasks,
          builder: (context, state) => const PersonnelTasksScreen(),
        ),
        GoRoute(
          path: RoutePaths.personnelWorkOrders,
          builder: (context, state) => const MyWorkOrdersScreen(),
          routes: [
            GoRoute(
              path: ':workOrderId',
              builder: (context, state) => PersonnelWorkOrderScreen(
                workOrderId: state.pathParameters['workOrderId']!,
              ),
              routes: [
                GoRoute(
                  path: 'materials',
                  builder: (context, state) => MaterialRequestScreen(
                    workOrderId: state.pathParameters['workOrderId']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: RoutePaths.personnelMaterials,
          builder: (context, state) => const PersonnelMaterialsScreen(),
        ),
        GoRoute(
          path: RoutePaths.personnelScanning,
          builder: (context, state) =>
              ScanResultScreen(code: state.uri.queryParameters['code'] ?? ''),
        ),
        GoRoute(
          path: RoutePaths.personnelAlerts,
          builder: (context, state) => const MobileAlertsScreen(
            homePath: RoutePaths.personnelDashboard,
            emptyMessage:
                'No notifications yet. You will be told here when work is '
                'assigned to you or a task is added.',
          ),
        ),
        GoRoute(
          path: RoutePaths.personnelProfile,
          builder: (context, state) => const MobileProfileScreen(),
        ),
      ],
    ),
  ],
);
