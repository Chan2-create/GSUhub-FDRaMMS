import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// A row of tabs over a rule: the open one in the brand's navy over a gold
/// rule, as the sidebar marks where you are. Settings drew it first (§29);
/// Inventory Management shares it (§33), so the console has one way of
/// splitting a page into topics.
///
/// A tab may carry a count in a gold pill ([countOf]: what waits on that
/// tab) or a gold dot ([markedOf]: something on it is not saved).
class ConsoleTabBar<T> extends StatelessWidget {
  const ConsoleTabBar({
    required this.tabs,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    this.countOf,
    this.markedOf,
    this.markLabel = 'unsaved changes',
    this.markTooltip = 'Unsaved changes',
    super.key,
  });

  final List<T> tabs;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T tab) labelOf;

  /// A count shown after the tab's name, when not null.
  final int? Function(T tab)? countOf;

  /// Whether the tab carries the dot.
  final bool Function(T tab)? markedOf;

  /// What a screen reader says of a marked tab, after its name.
  final String markLabel;

  /// The dot's tooltip.
  final String markTooltip;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    // Scrolls sideways on a phone rather than squeezing the names.
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs)
            _Tab(
              label: labelOf(tab),
              count: countOf?.call(tab),
              marked: markedOf?.call(tab) ?? false,
              markLabel: markLabel,
              markTooltip: markTooltip,
              selected: tab == selected,
              onTap: () => onSelected(tab),
            ),
        ],
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.marked,
    required this.markLabel,
    required this.markTooltip,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool marked;
  final String markLabel;
  final String markTooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: [
      if (count != null) '$label ($count)' else label,
      if (marked) markLabel,
    ].join(', '),
    excludeSemantics: true,
    child: InkWell(
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.accentGold : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.sectionTitle.copyWith(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accentGold,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  child: Text(
                    '$count',
                    style: AppTextStyles.badgeText.copyWith(
                      color: AppColors.sidebarBackground,
                    ),
                  ),
                ),
              ),
            ],
            if (marked) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: markTooltip,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accentGold,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 8),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// The tabs' pages. Every one stays built, so what was typed, filtered or
/// paged on a tab survives a look at another; only the open one is laid
/// out, painted, ticking and reachable by the keyboard.
class ConsoleTabPages<T> extends StatelessWidget {
  const ConsoleTabPages({
    required this.tabs,
    required this.open,
    required this.pageOf,
    super.key,
  });

  final List<T> tabs;
  final T open;
  final Widget Function(T tab) pageOf;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final tab in tabs)
        Offstage(
          offstage: tab != open,
          child: ExcludeFocus(
            excluding: tab != open,
            child: TickerMode(enabled: tab == open, child: pageOf(tab)),
          ),
        ),
    ],
  );
}
