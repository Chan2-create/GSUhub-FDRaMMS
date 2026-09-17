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
/// user block pinned to the bottom.
class AdminSidebar extends StatelessWidget {
  const AdminSidebar({
    required this.currentLocation,
    required this.user,
    required this.onSignOut,
    super.key,
  });

  static const double width = 305;

  final String currentLocation;
  final AuthUser? user;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: ColoredBox(
      color: AppColors.sidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 27, 22, 0),
            child: Text(
              'GSU Administration',
              style: AppTextStyles.sidebarTitle,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 24, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in adminNavGroups) ...[
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
                      ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          _UserFooter(user: user, onSignOut: onSignOut),
        ],
      ),
    ),
  );
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.isActive});

  final AdminNavItem item;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final foreground = isActive ? AppColors.onAccentGold : AppColors.textOnDark;

    final tile = Semantics(
      selected: isActive,
      button: true,
      enabled: item.isEnabled,
      child: InkWell(
        onTap: item.isEnabled && !isActive ? () => context.go(item.path) : null,
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

  Widget _icon(Color color) {
    final asset = item.iconAsset;
    if (asset == null) {
      // Only Map View lands here — its Figma node has no glyph.
      return Icon(Icons.location_on_outlined, size: 22, color: color);
    }
    return SvgPicture.asset(
      asset,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({required this.user, required this.onSignOut});

  final AuthUser? user;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final email = user?.email ?? '';
    final displayName = email.isEmpty ? 'Signed in' : email.split('@').first;

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
