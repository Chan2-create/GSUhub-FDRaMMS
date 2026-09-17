/// Named path constants for all three shells, path-prefixed in one router
/// (`/admin/*`, `/staff/*`, `/personnel/*` — see docs/architecture_decisions.md
/// "Router structure"). Screens not yet built resolve to a marked
/// placeholder; the owning WBS objective is noted per constant.
abstract final class RoutePaths {
  /// Redirects to the signed-in user's home area.
  static const String root = '/';

  // --- Admin (web) — WBS Objective 2 ---

  static const String adminLogin = '/admin/login';

  /// Admin dashboard — built in 2.A.
  static const String adminDashboard = '/admin/dashboard';

  /// Damage-report management — real UI lands in 2.B.
  static const String adminReports = '/admin/reports';

  /// Work-order assignment and Kanban board — real UI lands in 2.B.
  static const String adminWorkOrders = '/admin/work-orders';

  /// Inventory management — real UI lands in Objective 6.
  static const String adminInventory = '/admin/inventory';

  /// Maintenance personnel directory — real UI lands in 2.C.
  static const String adminPersonnel = '/admin/personnel';

  /// Task assignment — real UI lands in 2.B.
  static const String adminTaskAssignment = '/admin/task-assignment';

  /// Campus map view of reported issues.
  ///
  /// This item exists in the Figma sidebar (an icon at y=500 whose text
  /// label was lost) and has its own designed screens elsewhere in the
  /// file, but it is **not** in the manuscript's documented admin feature
  /// list — flagged for the adviser. Placeholder for now.
  static const String adminMapView = '/admin/map';

  /// Maintenance reports and analytics — real UI lands in 2.C.
  static const String adminAnalytics = '/admin/analytics';

  /// User account management — real UI lands in 2.C.
  static const String adminUsers = '/admin/users';

  /// Notification centre — real UI lands in a later objective.
  static const String adminNotifications = '/admin/notifications';

  /// System settings — real UI lands in a later objective.
  static const String adminSettings = '/admin/settings';

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
