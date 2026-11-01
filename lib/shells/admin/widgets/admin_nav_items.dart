import 'package:flutter/material.dart' show IconData, Icons;

import '../../../core/routing/route_paths.dart';

/// One entry in the admin sidebar.
class AdminNavItem {
  const AdminNavItem({
    required this.label,
    required this.iconAsset,
    required this.path,
    required this.isEnabled,
    this.disabledReason,
    this.fallbackIcon,
  });

  final String label;

  /// Path to the SVG exported from Figma, or null when the design
  /// supplied no glyph.
  final String? iconAsset;

  /// Drawn when [iconAsset] is null.
  final IconData? fallbackIcon;

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
/// Items resolve to a real screen as their objective landed: Dashboard in
/// 2.A; Damage Reports, Task Assignment and Work Order Management in 2.B;
/// Personnel, Analytics and User Accounts in 2.C; Inventory Management and
/// Facilities & Equipment in 6; Notifications in 7.A. Map View alone stays
/// disabled, with a tooltip saying why: it is drawn but not in the
/// manuscript's feature list. A tile that goes nowhere reads as broken; a
/// tile that says why reads as a decision.
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
        isEnabled: true,
      ),
      AdminNavItem(
        label: 'Inventory Management',
        iconAsset: 'assets/icons/nav_inventory.svg',
        path: RoutePaths.adminInventory,
        isEnabled: true,
      ),
      AdminNavItem(
        label: 'Personnel',
        iconAsset: 'assets/icons/nav_personnel.svg',
        path: RoutePaths.adminPersonnel,
        isEnabled: true,
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
        isEnabled: true,
      ),
      // Added from node 202:5355, which carries this item in its own
      // sidebar; the newer dashboard frame (196:534) never gained it, so
      // 2.A had no entry to build. Without it the screen has no way in.
      // The only deviation from the 2.A sidebar, and a deliberate one.
      AdminNavItem(
        label: 'Work Order Management',
        iconAsset: 'assets/icons/nav_tasks.svg',
        path: RoutePaths.adminWorkOrders,
        isEnabled: true,
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
        isEnabled: true,
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
        isEnabled: true,
      ),
      // Objective 6.C, no design: the rooms and equipment the QR codes
      // name. Beside User Accounts, the other registry the system keeps.
      AdminNavItem(
        label: 'Facilities & Equipment',
        iconAsset: null,
        fallbackIcon: Icons.meeting_room_outlined,
        path: RoutePaths.adminFacilities,
        isEnabled: true,
      ),
      // The notification centre (Objective 7.A, Figma 202:5608).
      AdminNavItem(
        label: 'Notifications',
        iconAsset: 'assets/icons/nav_notifications.svg',
        path: RoutePaths.adminNotifications,
        isEnabled: true,
      ),
      AdminNavItem(
        label: 'Settings',
        iconAsset: 'assets/icons/nav_settings.svg',
        path: RoutePaths.adminSettings,
        isEnabled: true,
      ),
    ],
  ),
];
