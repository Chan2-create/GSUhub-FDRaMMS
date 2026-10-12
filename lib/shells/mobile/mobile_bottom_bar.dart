import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// One tab of [MobileBottomBar].
class MobileTab {
  const MobileTab({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    this.badge = 0,
  });

  final String label;
  final String path;

  /// Material stand-ins for the design's glyphs, whose SVGs could not be
  /// exported. The current tab's glyph is filled, as drawn.
  final IconData icon;
  final IconData selectedIcon;

  /// Unread count shown on the tab, or 0 for none.
  final int badge;
}

/// The mobile apps' floating bottom bar: four tabs on a gold-edged pill,
/// and the raised gold "+" between them (Figma `170:2050`, `166:2261`; the
/// personnel frames of Figures 24 and 25 draw the same bar).
class MobileBottomBar extends StatelessWidget {
  const MobileBottomBar({
    required this.tabs,
    required this.location,
    required this.selected,
    required this.actionLabel,
    required this.onAction,
    super.key,
  }) : assert(tabs.length == 4, 'Two tabs either side of the button');

  /// Where the app is. Tapping the current tab from a page under it (a
  /// report's or a work order's detail) returns to the tab's own page.
  final String location;

  /// Left to right; the button sits between the second and the third.
  final List<MobileTab> tabs;

  /// The tab the current page belongs to, or null for none.
  final MobileTab? selected;

  /// What the gold "+" does, for its tooltip and screen readers.
  final String actionLabel;
  final VoidCallback onAction;

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
                  _item(context, tabs[0]),
                  _item(context, tabs[1]),
                  // The raised button's slot.
                  const Expanded(child: SizedBox()),
                  _item(context, tabs[2]),
                  _item(context, tabs[3]),
                ],
              ),
            ),
            Positioned(
              top: 0,
              child: _ActionButton(
                size: _fabSize,
                label: actionLabel,
                onPressed: onAction,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _item(BuildContext context, MobileTab tab) {
    final isSelected = tab.path == selected?.path;
    final icon = Icon(
      isSelected ? tab.selectedIcon : tab.icon,
      size: 22,
      color: AppColors.primary,
    );
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: tab.badge > 0 ? '${tab.label}, ${tab.badge} unread' : tab.label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: location == tab.path ? null : () => context.go(tab.path),
          radius: 30,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (tab.badge > 0)
                Badge(
                  label: Text(tab.badge > 99 ? '99+' : '${tab.badge}'),
                  backgroundColor: AppColors.notificationBadge,
                  textColor: Colors.white,
                  child: icon,
                )
              else
                icon,
              Text(
                tab.label,
                style: AppTextStyles.navLabel.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The raised gold "+".
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.size,
    required this.label,
    required this.onPressed,
  });

  final double size;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
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

/// The bottom padding a page inside a mobile shell needs so its last item
/// clears the floating bar.
double mobileBottomInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 16;
