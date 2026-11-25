import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/press_scale.dart';
import '../page_refresh.dart';

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

/// The mobile apps' floating bottom bar: the tabs on a gold-edged pill,
/// and the raised gold "+" between them (Figma `170:2050`, `166:2261`; the
/// personnel frames of Figures 24 and 25 draw the same bar).
///
/// Four tabs as drawn, two each side; since 2026-11-26 the faculty and
/// staff app has three (no Alerts tab: the header's bell opens the
/// notifications), the third centred in the right half. Each tab shows
/// its own unread count as a number.
class MobileBottomBar extends StatelessWidget {
  const MobileBottomBar({
    required this.tabs,
    required this.location,
    required this.selected,
    required this.actionLabel,
    required this.onAction,
    super.key,
  }) : assert(
         tabs.length >= 2 && tabs.length <= 4,
         'One or two tabs either side of the button',
       );

  /// Where the app is. Tapping the current tab from a page under it (a
  /// report's or a work order's detail) returns to the tab's own page.
  final String location;

  /// Left to right; the button sits after the first half, the larger
  /// half on the left.
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
              // Two halves around the button's slot, so the button stays
              // in the middle whatever the number of tabs.
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        for (final tab in tabs.take(_leftCount))
                          _item(context, tab),
                      ],
                    ),
                  ),
                  // The raised button's slot.
                  const Expanded(child: SizedBox()),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        for (final tab in tabs.skip(_leftCount))
                          _item(context, tab),
                      ],
                    ),
                  ),
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

  /// The tabs left of the button: the first half, the larger one.
  int get _leftCount => (tabs.length + 1) ~/ 2;

  Widget _item(BuildContext context, MobileTab tab) {
    final isSelected = tab.path == selected?.path;
    final icon = Icon(
      isSelected ? tab.selectedIcon : tab.icon,
      size: 22,
      color: AppColors.primary,
    );
    return Expanded(
      child: Semantics(
        container: true,
        button: true,
        selected: isSelected,
        label: tab.badge > 0 ? '${tab.label}, ${tab.badge} unread' : tab.label,
        excludeSemantics: true,
        child: InkResponse(
          // Pressed again, the tab's page is read again; from a page
          // under the tab, it returns to the tab's own page first
          // (2026-11-25).
          onTap: () => navigateFromNav(
            context,
            location: location,
            target: tab.path,
            inModule: isSelected,
          ),
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
    child: PressScale(
      scale: 0.94,
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
    ),
  );
}

/// The bottom padding a page inside a mobile shell needs so its last item
/// clears the floating bar.
double mobileBottomInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 16;
