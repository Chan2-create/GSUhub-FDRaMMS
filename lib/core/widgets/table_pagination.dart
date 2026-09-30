import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// Which of the designs' pagination strips to draw.
enum TablePaginationStyle {
  /// Damage Reports (Figma `198:2947`): numbered pages between arrows.
  numbered,

  /// Maintenance Personnel (Figma `201:4851`): previous and next only.
  arrows,

  /// User Accounts (Figma `89:4885`): a rows-per-page picker, then first,
  /// previous, numbered pages, next and last.
  full,
}

/// "Showing 1 to 10 of 42 results" with page controls.
///
/// Stateless: the caller owns the page index, so a filter change can reset
/// it to the first page in the same place the filter is applied.
class TablePagination extends StatelessWidget {
  const TablePagination({
    required this.page,
    required this.pageSize,
    required this.totalItems,
    required this.onPageChanged,
    super.key,
    this.style = TablePaginationStyle.numbered,
    this.itemNoun = 'results',
    this.pageSizeOptions = const [10, 25, 50],
    this.onPageSizeChanged,
  });

  /// Zero-based page index.
  final int page;
  final int pageSize;
  final int totalItems;
  final ValueChanged<int> onPageChanged;
  final TablePaginationStyle style;

  /// What is being counted — "results", "staff members", "users".
  final String itemNoun;

  /// Choices for the [TablePaginationStyle.full] rows-per-page picker.
  final List<int> pageSizeOptions;
  final ValueChanged<int>? onPageSizeChanged;

  int get pageCount => totalItems == 0 ? 1 : (totalItems / pageSize).ceil();

  String get _summary {
    final first = totalItems == 0 ? 0 : page * pageSize + 1;
    final last = ((page + 1) * pageSize).clamp(0, totalItems);
    return 'Showing $first to $last of $totalItems $itemNoun';
  }

  VoidCallback? get _previous =>
      page > 0 ? () => onPageChanged(page - 1) : null;

  VoidCallback? get _next =>
      page < pageCount - 1 ? () => onPageChanged(page + 1) : null;

  @override
  Widget build(BuildContext context) => switch (style) {
    TablePaginationStyle.numbered => _numbered(),
    TablePaginationStyle.arrows => _arrows(),
    TablePaginationStyle.full => _full(),
  };

  Widget _numbered() => Container(
    // Wrap sizes to its content, so without this the strip would sit as
    // a narrow island in the middle of the card instead of spanning it.
    width: double.infinity,
    decoration: const BoxDecoration(
      color: AppColors.surfaceTint,
      border: Border(top: BorderSide(color: AppColors.borderStrong)),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
    ),
    padding: const EdgeInsets.fromLTRB(24, 25, 24, 24),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      spacing: 24,
      children: [
        Text(_summary, style: AppTextStyles.paginationSummary),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ArrowButton(
              asset: 'assets/icons/page_prev.svg',
              tooltip: 'Previous page',
              onPressed: _previous,
            ),
            const SizedBox(width: 4),
            ..._pageButtons(spacing: 4),
            _ArrowButton(
              asset: 'assets/icons/page_next.svg',
              tooltip: 'Next page',
              onPressed: _next,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _arrows() => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      color: AppColors.tableStripe,
      border: Border(top: BorderSide(color: AppColors.borderStrong)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 17, 16, 16),
    child: Row(
      children: [
        Expanded(child: Text(_summary, style: AppTextStyles.tableFooterText)),
        _ArrowButton(
          asset: 'assets/icons/page_prev.svg',
          tooltip: 'Previous page',
          onPressed: _previous,
          padding: const EdgeInsets.all(9),
        ),
        const SizedBox(width: 8),
        _ArrowButton(
          asset: 'assets/icons/page_next.svg',
          tooltip: 'Next page',
          onPressed: _next,
          padding: const EdgeInsets.all(9),
        ),
      ],
    ),
  );

  Widget _full() {
    final onSize = onPageSizeChanged;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderStrong)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 25),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        spacing: 24,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_summary, style: AppTextStyles.tableFooterText),
              if (onSize != null) ...[
                const SizedBox(width: 24),
                const Text(
                  'Rows per page:',
                  style: AppTextStyles.tableFooterText,
                ),
                const SizedBox(width: 8),
                _PageSizePicker(
                  value: pageSize,
                  options: pageSizeOptions,
                  onChanged: onSize,
                ),
              ],
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconPageButton(
                icon: Icons.first_page,
                tooltip: 'First page',
                onPressed: page > 0 ? () => onPageChanged(0) : null,
              ),
              _IconPageButton(
                icon: Icons.chevron_left,
                tooltip: 'Previous page',
                onPressed: _previous,
              ),
              const SizedBox(width: 20),
              ..._pageButtons(spacing: 4, square: true),
              const SizedBox(width: 20),
              _IconPageButton(
                icon: Icons.chevron_right,
                tooltip: 'Next page',
                onPressed: _next,
              ),
              _IconPageButton(
                icon: Icons.last_page,
                tooltip: 'Last page',
                onPressed: page < pageCount - 1
                    ? () => onPageChanged(pageCount - 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _pageButtons({required double spacing, bool square = false}) => [
    for (final entry in pageWindow(page, pageCount)) ...[
      if (entry == null)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: AppTextStyles.pageSubtitle),
        )
      else
        _PageButton(
          number: entry + 1,
          selected: entry == page,
          square: square,
          onPressed: () => onPageChanged(entry),
        ),
      SizedBox(width: spacing),
    ],
  ];

  /// Page indices to show, with `null` standing for an ellipsis — the
  /// design's "1 2 3 ... 32": the first three pages, then the last, with
  /// the current page and its neighbours always visible.
  static List<int?> pageWindow(int page, int pageCount) {
    if (pageCount <= 5) return [for (var i = 0; i < pageCount; i++) i];

    final visible = <int>{
      0,
      1,
      2,
      pageCount - 1,
      if (page > 0) page - 1,
      page,
      if (page < pageCount - 1) page + 1,
    }.toList()..sort();

    final result = <int?>[];
    for (var i = 0; i < visible.length; i++) {
      if (i > 0 && visible[i] - visible[i - 1] > 1) result.add(null);
      result.add(visible[i]);
    }
    return result;
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.number,
    required this.selected,
    required this.onPressed,
    this.square = false,
  });

  final int number;
  final bool selected;
  final bool square;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: 'Page $number',
    child: InkWell(
      onTap: selected ? null : onPressed,
      borderRadius: BorderRadius.circular(square ? 4 : 2),
      child: Container(
        width: square ? 32 : null,
        height: square ? 32 : null,
        alignment: square ? Alignment.center : null,
        padding: square
            ? null
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : null,
          borderRadius: BorderRadius.circular(square ? 4 : 2),
        ),
        child: Text(
          '$number',
          style: AppTextStyles.paginationPage.copyWith(
            color: selected ? AppColors.textOnDark : null,
          ),
        ),
      ),
    ),
  );
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.asset,
    required this.tooltip,
    required this.onPressed,
    this.padding = const EdgeInsets.all(5),
  });

  final String asset;
  final String tooltip;
  final VoidCallback? onPressed;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(2),
      child: Opacity(
        // The design's disabled "previous" arrow at 50%.
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderStrong),
            borderRadius: BorderRadius.circular(2),
          ),
          child: SvgPicture.asset(asset, width: 7.4, height: 12),
        ),
      ),
    ),
  );
}

/// First/previous/next/last in the full strip — bare glyphs, no border.
class _IconPageButton extends StatelessWidget {
  const _IconPageButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 20,
          color: onPressed == null ? AppColors.textFaint : AppColors.iconMuted,
        ),
      ),
    ),
  );
}

class _PageSizePicker extends StatelessWidget {
  const _PageSizePicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: 'Rows per page',
    initialValue: value,
    onSelected: onChanged,
    position: PopupMenuPosition.under,
    itemBuilder: (context) => [
      for (final option in options)
        PopupMenuItem(value: option, child: Text('$option')),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: AppTextStyles.tableFooterText.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.expand_more, size: 20, color: AppColors.iconMuted),
        ],
      ),
    ),
  );
}
