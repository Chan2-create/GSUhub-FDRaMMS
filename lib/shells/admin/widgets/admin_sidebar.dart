import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/auth_service.dart';
import 'admin_nav_items.dart';

/// Persistent admin navigation rail (Figma node `196:534`).
///
/// Indigo panel, gold pill on the active item, grouped sections, and a
/// user block pinned to the bottom. Narrower than the design allows
/// (Breakpoints.expanded), [rail] draws the same items as icons with
/// their names in tooltips; on a phone the shell puts the full panel in
/// a drawer.
class AdminSidebar extends StatelessWidget {
  const AdminSidebar({
    required this.currentLocation,
    required this.user,
    required this.onSignOut,
    this.badges = const {},
    this.rail = false,
    super.key,
  });

  static const double width = 305;

  /// The icon rail's width.
  static const double railWidth = 76;

  /// Counts drawn on items, by path: the low-stock alerts on Inventory
  /// Management (Objective 6.A, §1.5).
  final Map<String, int> badges;

  final String currentLocation;
  final AuthUser? user;
  final VoidCallback onSignOut;

  /// Icons only.
  final bool rail;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: rail ? railWidth : width,
    child: ColoredBox(
      color: AppColors.sidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!rail)
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 27, 22, 0),
              child: Text(
                'GSU Administration',
                style: AppTextStyles.sidebarTitle,
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(top: rail ? 20 : 24, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in adminNavGroups) ...[
                    if (rail)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Divider(height: 1, color: Color(0x33FFFFFF)),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 6),
                        child: Text(
                          group.label,
                          style: AppTextStyles.sidebarGroupLabel,
                        ),
                      ),
                    for (final item in group.items)
                      _NavTile(
                        item: item,
                        isActive: currentLocation.startsWith(item.path),
                        badge: badges[item.path] ?? 0,
                        rail: rail,
                      ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          _UserFooter(user: user, onSignOut: onSignOut, rail: rail),
        ],
      ),
    ),
  );
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.isActive,
    this.badge = 0,
    this.rail = false,
  });

  final AdminNavItem item;
  final bool isActive;

  /// Above zero, a red count after the label.
  final int badge;

  final bool rail;

  @override
  Widget build(BuildContext context) {
    final foreground = isActive ? AppColors.onAccentGold : AppColors.textOnDark;

    if (rail) return _railTile(context, foreground);

    final tile = Semantics(
      selected: isActive,
      button: true,
      enabled: item.isEnabled,
      label: badge > 0 ? '${item.label}, $badge low on stock' : null,
      child: InkWell(
        onTap: item.isEnabled && !isActive ? () => _go(context) : null,
        child: Container(
          height: 45,
          decoration: isActive
              ? BoxDecoration(
                  color: AppColors.accentGold,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      offset: Offset(0, 4),
                      blurRadius: 4,
                    ),
                  ],
                )
              : null,
          child: Row(
            children: [
              const SizedBox(width: 13),
              SizedBox(width: 24, height: 24, child: _icon(foreground)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  style: isActive
                      ? AppTextStyles.sidebarItemActive
                      : AppTextStyles.sidebarItem,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge > 0)
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.notificationBadge,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: AppTextStyles.badgeText.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );

    if (item.isEnabled) return tile;

    return Tooltip(
      message: item.disabledReason ?? 'Not available yet.',
      child: Opacity(opacity: 0.55, child: tile),
    );
  }

  /// In the drawer, the panel closes as the page changes.
  void _go(BuildContext context) {
    Scaffold.maybeOf(context)?.closeDrawer();
    context.go(item.path);
  }

  /// The rail's tile: the icon in the gold pill, the name in a tooltip,
  /// the count as a red bubble on the icon.
  Widget _railTile(BuildContext context, Color foreground) {
    final tile = Semantics(
      selected: isActive,
      button: true,
      enabled: item.isEnabled,
      label: badge > 0 ? '${item.label}, $badge low on stock' : item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: item.isEnabled && !isActive ? () => _go(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 45,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: isActive
              ? BoxDecoration(
                  color: AppColors.accentGold,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      offset: Offset(0, 4),
                      blurRadius: 4,
                    ),
                  ],
                )
              : null,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(width: 24, height: 24, child: _icon(foreground)),
                if (badge > 0)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.notificationBadge,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: AppTextStyles.badgeText.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: item.isEnabled
          ? item.label
          : '${item.label}: ${item.disabledReason ?? 'Not available yet.'}',
      child: item.isEnabled ? tile : Opacity(opacity: 0.55, child: tile),
    );
  }

  Widget _icon(Color color) {
    final asset = item.iconAsset;
    if (asset == null) {
      // Map View's Figma node has no glyph; Facilities & Equipment has no
      // design at all.
      return Icon(
        item.fallbackIcon ?? Icons.location_on_outlined,
        size: 22,
        color: color,
      );
    }
    return SvgPicture.asset(
      asset,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.user,
    required this.onSignOut,
    this.rail = false,
  });

  final AuthUser? user;
  final VoidCallback onSignOut;
  final bool rail;

  @override
  Widget build(BuildContext context) {
    final email = user?.email ?? '';
    final displayName = email.isEmpty ? 'Signed in' : email.split('@').first;

    if (rail) {
      return Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: Color(0xB8000000))),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Tooltip(
              message: '$displayName · System Administrator',
              child: Container(
                width: 34,
                height: 31,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.sidebarBackground,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials(displayName),
                  style: AppTextStyles.sidebarFooterName.copyWith(
                    color: AppColors.accentGold,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: onSignOut,
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout, size: 18),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 67,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0xB8000000))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 31,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.sidebarBackground,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(displayName),
              style: AppTextStyles.sidebarFooterName.copyWith(
                color: AppColors.accentGold,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: AppTextStyles.sidebarFooterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'System Administrator',
                  style: AppTextStyles.sidebarFooterRole,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onSignOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, size: 18),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.length == 1
        ? trimmed.toUpperCase()
        : trimmed.substring(0, 2).toUpperCase();
  }
}
