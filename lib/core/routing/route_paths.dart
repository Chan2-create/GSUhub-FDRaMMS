/// Named path constants for all three shells, path-prefixed in one router
/// (`/admin/*`, `/staff/*`, `/personnel/*` — see docs/architecture_decisions.md
/// "Router structure" for why one router over three separate entry points).
/// Every screen behind these paths is a bare placeholder until its owning
/// WBS objective (noted per constant, from `GSUhub_WBS_Simplified`) builds
/// the real UI.
abstract final class RoutePaths {
  /// Redirects to [adminDashboard]. No dedicated screen of its own.
  static const String root = '/';

  // --- Admin (web) — WBS Objective 2 ---

  /// Admin authentication — real UI and RBAC enforcement land in 2.A.
  static const String adminLogin = '/admin/login';

  /// Admin dashboard + main layout — real UI lands in 2.A.
  static const String adminDashboard = '/admin/dashboard';

  /// Damage-report management and Kanban work-order tracking — real UI
  /// lands in 2.B.
  static const String adminReports = '/admin/reports';

  static const String adminWorkOrders = '/admin/work-orders';

  /// User account management — real UI lands in 2.C.
  static const String adminUsers = '/admin/users';

  /// Maintenance reports/analytics view — real UI lands in 2.C.
  static const String adminAnalytics = '/admin/analytics';

  // --- Requestor (Faculty/Staff, mobile) — WBS Objective 3 ---

  static const String staffLogin = '/staff/login';

  /// Facility damage report submission — real UI lands in 3.A.
  static const String staffSubmitReport = '/staff/submit';

  /// Real-time status tracking of submitted reports — real UI lands in
  /// 3.B.
  static const String staffMyReports = '/staff/reports';

  /// Post-service feedback and rating — real UI lands in 3.C.
  static const String staffFeedback = '/staff/feedback';

  // --- Maintenance Personnel (mobile) — WBS Objective 5 ---

  static const String personnelLogin = '/personnel/login';

  /// Personnel dashboard, task list, work-order detail — real UI lands in
  /// 5.A.
  static const String personnelDashboard = '/personnel/dashboard';

  /// Work-order status updates + accomplishment reporting — real UI lands
  /// in 5.B.
  static const String personnelWorkOrders = '/personnel/work-orders';

  /// QR/barcode scanning for material and tool usage — real UI lands in
  /// 5.C.
  static const String personnelScanning = '/personnel/scan';
}
