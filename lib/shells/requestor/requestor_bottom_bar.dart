import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../mobile/mobile_bottom_bar.dart';

/// The four tabs of the faculty and staff app (Figma `170:2050`, "Group
/// 6"): Home and Reports, the gold +, Notifications and Profile.
///
/// Notifications left the bar for the header's bell on 2026-11-26, which
/// left three tabs around the +, lopsided; it is back, and the header has
/// Help in the bell's place. It carries the unread count.
enum RequestorTab {
  home('Home', RoutePaths.staffHome, Icons.home_outlined, Icons.home_rounded),
  reports(
    'Reports',
    RoutePaths.staffMyReports,
    Icons.assignment_outlined,
    Icons.assignment_rounded,
  ),
  alerts(
    'Notifications',
    RoutePaths.staffAlerts,
    Icons.notifications_none_rounded,
    Icons.notifications_rounded,
  ),
  profile(
    'Profile',
    RoutePaths.staffProfile,
    Icons.person_outline_rounded,
    Icons.person_rounded,
  );

  const RequestorTab(this.label, this.path, this.icon, this.selectedIcon);

  final String label;
  final String path;

  /// Material stand-ins for the design's glyphs, whose SVGs could not be
  /// exported. The design fills the current tab's glyph (Home, filled,
  /// beside outlined others), so the stand-ins do the same.
  final IconData icon;
  final IconData selectedIcon;

  /// The tab [location] belongs to, or null for a page outside the tabs.
  /// A report's detail page sits under Reports.
  static RequestorTab? of(String location) {
    for (final tab in values) {
      if (location == tab.path || location.startsWith('${tab.path}/')) {
        return tab;
      }
    }
    return null;
  }
}

/// The floating bottom bar: the tabs on a gold-edged pill, and the raised
/// gold button between them that opens the report form (Figma `170:2050`,
/// `166:2261`). The shared [MobileBottomBar], with the faculty tabs.
class RequestorBottomBar extends StatelessWidget {
  const RequestorBottomBar({
    required this.location,
    super.key,
    this.badges = const {},
  });

  /// Where the app is. Its tab is highlighted; tapping that tab again from
  /// a page under it (a report's detail) returns to the tab's own page.
  final String location;

  /// Unread notices by tab path, each shown as a number on its tab
  /// (2026-11-26). The design draws no badge; it takes the console bell's
  /// red.
  final Map<String, int> badges;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      for (final tab in RequestorTab.values)
        MobileTab(
          label: tab.label,
          path: tab.path,
          icon: tab.icon,
          selectedIcon: tab.selectedIcon,
          badge: badges[tab.path] ?? 0,
        ),
    ];
    final current = RequestorTab.of(location);
    return MobileBottomBar(
      tabs: tabs,
      location: location,
      selected: current == null ? null : tabs[current.index],
      actionLabel: 'Report damage',
      onAction: () => context.push(RoutePaths.staffSubmitReport),
    );
  }
}
