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

  /// Damage-report management — built in 2.B.
  static const String adminReports = '/admin/reports';

  /// One report, read-only in 2.B: the controls for confirming category
  /// and priority arrive in 4.C.
  static const String adminReportDetail = '/admin/reports/:reportId';

  /// Link to [adminReportDetail] for a given report.
  static String adminReportDetailFor(String reportId) =>
      '/admin/reports/$reportId';

  /// Work-order management and Kanban board — built in 2.B.
  static const String adminWorkOrders = '/admin/work-orders';

  /// One work order: tasks, the note to the technician, materials and
  /// tools, and the accomplishment report to review (Objective 5).
  static const String adminWorkOrderDetail = '/admin/work-orders/:workOrderId';

  /// Link to [adminWorkOrderDetail] for one work order.
  static String adminWorkOrderDetailFor(String workOrderId) =>
      '/admin/work-orders/$workOrderId';

  /// Inventory management — real UI lands in Objective 6.
  static const String adminInventory = '/admin/inventory';

  /// Maintenance personnel directory (Objective 2.C).
  static const String adminPersonnel = '/admin/personnel';

  /// Task assignment — built in 2.B.
  static const String adminTaskAssignment = '/admin/task-assignment';

  /// Opens task assignment with one report already selected, from the
  /// assign action on a row of the reports table.
  static String adminTaskAssignmentFor(String reportId) =>
      '$adminTaskAssignment?report=$reportId';

  /// Campus map view of reported issues.
  ///
  /// This item exists in the Figma sidebar (an icon at y=500 whose text
  /// label was lost) and has its own designed screens elsewhere in the
  /// file, but it is **not** in the manuscript's documented admin feature
  /// list — flagged for the adviser. Placeholder for now.
  static const String adminMapView = '/admin/map';

  /// Maintenance analytics and the CSV export (Objective 2.C).
  static const String adminAnalytics = '/admin/analytics';

  /// User account management (Objective 2.C).
  static const String adminUsers = '/admin/users';

  /// Notification centre — real UI lands in a later objective.
  static const String adminNotifications = '/admin/notifications';

  /// Settings: the classification keywords (Objective 4.A).
  static const String adminSettings = '/admin/settings';

  // --- Requestor (Faculty/Staff, mobile) — WBS Objective 3 ---

  /// Faculty and staff sign-in (Objective 3.A, Figma `193:310`).
  static const String staffLogin = '/staff/login';

  /// Self-registration, pending approval (Objective 3.A, Figma `194:455`).
  static const String staffSignUp = '/staff/signup';

  /// The requestor's home: greeting, quick actions, overview, recent
  /// reports (Objective 3.A, Figma `170:2050`).
  static const String staffHome = '/staff/home';

  /// Facility damage report submission (Objective 3.C, Figma `165:137`).
  /// Opened over the tabs from the bottom bar's centre button.
  static const String staffSubmitReport = '/staff/submit';

  /// My Reports — the requestor's own reports, searchable and filtered
  /// (Objective 3.A, Figma `169:1251`), live since 3.B.
  static const String staffMyReports = '/staff/reports';

  /// One of the requestor's reports and how it is progressing, with its
  /// status timeline (Objective 3.B, Figma `169:1355`). Notifications
  /// deep-link here.
  static const String staffReportDetail = '/staff/reports/:reportId';

  /// Link to [staffReportDetail] for a given report.
  static String staffReportDetailFor(String reportId) =>
      '/staff/reports/$reportId';

  /// Notifications — the Alerts tab (Objective 3.B, Figma `169:1459`).
  static const String staffAlerts = '/staff/alerts';

  /// The requestor's profile — a marked placeholder in 3.A, holding only
  /// sign-out.
  static const String staffProfile = '/staff/profile';

  /// Rating the service on one of the requestor's completed reports
  /// (Objective 3.C, Figma `169:1797`). Rating closes the report.
  static const String staffRateReport = '/staff/reports/:reportId/rate';

  /// Link to [staffRateReport] for a given report.
  static String staffRateReportFor(String reportId) =>
      '/staff/reports/$reportId/rate';

  // --- Maintenance Personnel (mobile) — WBS Objective 5 ---
  //
  // Personnel sign in on the mobile app's one sign-in page, [staffLogin]
  // (Chris, 2026-10-12): the account's role decides where it lands.

  /// Home: today's to-do and the technician's work orders (5.A,
  /// Figure 24).
  static const String personnelDashboard = '/personnel/dashboard';

  /// The Tasks tab: today's progress and every open task (5.A,
  /// Figure 24).
  static const String personnelTasks = '/personnel/tasks';

  /// My Work Orders, as a list or a board (5.A, Figure 25).
  static const String personnelWorkOrders = '/personnel/work-orders';

  /// One work order: its status, tasks, materials and tools, and the
  /// accomplishment report (5.A–5.C, Figure 25).
  static const String personnelWorkOrderDetail =
      '/personnel/work-orders/:workOrderId';

  /// Link to [personnelWorkOrderDetail] for one work order.
  static String personnelWorkOrderFor(String workOrderId) =>
      '/personnel/work-orders/$workOrderId';

  /// The Materials tab: tools held, materials recorded (5.C).
  static const String personnelMaterials = '/personnel/materials';

  /// What a scanned code identified (5.C): the gold "+" scans, then
  /// opens this with the code.
  static const String personnelScanning = '/personnel/scan';

  /// Link to [personnelScanning] for a scanned [code].
  static String personnelScanFor(String code) =>
      '/personnel/scan?code=${Uri.encodeQueryComponent(code)}';

  /// Notifications, opened from the header's bell.
  static const String personnelAlerts = '/personnel/alerts';

  /// The Profile tab.
  static const String personnelProfile = '/personnel/profile';
}
