import '../../../core/routing/route_paths.dart';

/// One entry in the admin sidebar.
class AdminNavItem {
  const AdminNavItem({
    required this.label,
    required this.iconAsset,
    required this.path,
    required this.isEnabled,
    this.disabledReason,
  });

  final String label;

  /// Path to the SVG exported from Figma, or null when the design
  /// supplied no glyph.
  final String? iconAsset;

  final String path;

  /// Whether the destination is built yet. Only Dashboard is, in 2.A.
  final bool isEnabled;

  /// Tooltip shown on a disabled item, naming the objective that builds
  /// it — so a teammate clicking around knows this is unfinished rather
  /// than broken.
  final String? disabledReason;
}

/// A titled group of sidebar entries ("Overview", "Management", "System").
class AdminNavGroup {
  const AdminNavGroup({required this.label, required this.items});

  final String label;
  final List<AdminNavItem> items;
}

/// The sidebar structure, read from Figma node `196:534` in the order and
/// grouping the design specifies.
///
/// Every item except Dashboard is disabled: the brief for 2.A is explicit
/// that only Dashboard routes anywhere, and the other screens belong to
/// later objectives.
const List<AdminNavGroup> adminNavGroups = [
  AdminNavGroup(
    label: 'Overview',
    items: [
      AdminNavItem(
        label: 'Dashboard',
        iconAsset: 'assets/icons/nav_dashboard.svg',
        path: RoutePaths.adminDashboard,
        isEnabled: true,
      ),
      AdminNavItem(
        label: 'Damage Reports',
        iconAsset: 'assets/icons/nav_reports.svg',
        path: RoutePaths.adminReports,
        isEnabled: false,
        disabledReason: 'Damage report management arrives in Objective 2.B.',
      ),
      AdminNavItem(
        label: 'Inventory Management',
        iconAsset: 'assets/icons/nav_inventory.svg',
        path: RoutePaths.adminInventory,
        isEnabled: false,
        disabledReason: 'Inventory management arrives in Objective 6.',
      ),
      AdminNavItem(
        label: 'Personnel',
        iconAsset: 'assets/icons/nav_personnel.svg',
        path: RoutePaths.adminPersonnel,
        isEnabled: false,
        disabledReason: 'Personnel management arrives in Objective 2.C.',
      ),
    ],
  ),
  AdminNavGroup(
    label: 'Management',
    items: [
      AdminNavItem(
        label: 'Task Assignment',
        iconAsset: 'assets/icons/nav_tasks.svg',
        path: RoutePaths.adminTaskAssignment,
        isEnabled: false,
        disabledReason: 'Task assignment arrives in Objective 2.B.',
      ),
      // The Figma node for this item carries no glyph (an empty 24px
      // frame at y=500), so there is no asset to export. Falls back to a
      // Material location pin — see docs and the fidelity report.
      AdminNavItem(
        label: 'Map View',
        iconAsset: null,
        path: RoutePaths.adminMapView,
        isEnabled: false,
        disabledReason:
            'Campus map view is designed but not in the manuscript feature '
            'list — pending adviser confirmation.',
      ),
      AdminNavItem(
        label: 'Analytics',
        iconAsset: 'assets/icons/nav_analytics.svg',
        path: RoutePaths.adminAnalytics,
        isEnabled: false,
        disabledReason: 'Analytics arrives in Objective 2.C.',
      ),
    ],
  ),
  AdminNavGroup(
    label: 'System',
    items: [
      AdminNavItem(
        label: 'User Accounts',
        iconAsset: 'assets/icons/nav_users.svg',
        path: RoutePaths.adminUsers,
        isEnabled: false,
        disabledReason: 'User account management arrives in Objective 2.C.',
      ),
      AdminNavItem(
        label: 'Notifications',
        iconAsset: 'assets/icons/nav_notifications.svg',
        path: RoutePaths.adminNotifications,
        isEnabled: false,
        disabledReason: 'The notification centre arrives in a later objective.',
      ),
      AdminNavItem(
        label: 'Settings',
        iconAsset: 'assets/icons/nav_settings.svg',
        path: RoutePaths.adminSettings,
        isEnabled: false,
        disabledReason: 'System settings arrive in a later objective.',
      ),
    ],
  ),
];
