import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/routing/route_paths.dart';

/// The four tabs of the faculty and staff app (Figma `170:2050`, "Group
/// 6"). Alerts and Profile are marked placeholders in 3.A.
enum RequestorTab {
  home('Home', RoutePaths.staffHome, Icons.home_outlined, Icons.home_rounded),
  reports(
    'Reports',
    RoutePaths.staffMyReports,
    Icons.assignment_outlined,
    Icons.assignment_rounded,
  ),
  alerts(
    'Alerts',
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

/// The floating bottom bar: four tabs on a gold-edged pill, and the raised
/// gold button between them that opens the report form (Figma `170:2050`,
/// `166:2261`).
class RequestorBottomBar extends StatelessWidget {
  const RequestorBottomBar({required this.location, super.key});

  /// Where the app is. Its tab is highlighted; tapping that tab again from
  /// a page under it (a report's detail) returns to the tab's own page.
  final String location;

  /// The pill's height, the button's diameter, and how far it rises above
  /// the pill's top edge.
  static const double _pillHeight = 65;
  static const double _fabSize = 55;
  static const double _fabRise = 28;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: _pillHeight + _fabRise,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              height: _pillHeight,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.navBar,
                borderRadius: BorderRadius.circular(_pillHeight / 2),
                border: Border.all(color: AppColors.accentGold, width: 2),
              ),
              child: Row(
                children: [
                  _item(context, RequestorTab.home),
                  _item(context, RequestorTab.reports),
                  // The raised button's slot.
                  const Expanded(child: SizedBox()),
                  _item(context, RequestorTab.alerts),
                  _item(context, RequestorTab.profile),
                ],
              ),
            ),
            Positioned(
              top: 0,
              child: _ReportButton(
                size: _fabSize,
                onPressed: () => context.push(RoutePaths.staffSubmitReport),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _item(BuildContext context, RequestorTab tab) {
    final selected = tab == RequestorTab.of(location);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: location == tab.path ? null : () => context.go(tab.path),
          radius: 30,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? tab.selectedIcon : tab.icon,
                size: 22,
                color: AppColors.primary,
              ),
              Text(
                tab.label,
                style: AppTextStyles.navLabel.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The raised gold "+" — opens the damage report form.
class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.size, required this.onPressed});

  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Report damage',
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.accentGold,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.navFabGlow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ),
      ),
    ),
  );
}
