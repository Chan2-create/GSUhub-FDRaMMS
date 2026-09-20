import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// "Showing 1 to 10 of 42 results" with numbered page buttons
/// (Figma `198:2947`).
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
  });

  /// Zero-based page index.
  final int page;
  final int pageSize;
  final int totalItems;
  final ValueChanged<int> onPageChanged;

  int get pageCount => totalItems == 0 ? 1 : (totalItems / pageSize).ceil();

  @override
  Widget build(BuildContext context) {
    final first = totalItems == 0 ? 0 : page * pageSize + 1;
    final last = ((page + 1) * pageSize).clamp(0, totalItems);

    return Container(
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
          Text(
            'Showing $first to $last of $totalItems results',
            style: AppTextStyles.paginationSummary,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ArrowButton(
                asset: 'assets/icons/page_prev.svg',
                tooltip: 'Previous page',
                onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
              ),
              const SizedBox(width: 4),
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
                    onPressed: () => onPageChanged(entry),
                  ),
                const SizedBox(width: 4),
              ],
              _ArrowButton(
                asset: 'assets/icons/page_next.svg',
                tooltip: 'Next page',
                onPressed: page < pageCount - 1
                    ? () => onPageChanged(page + 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

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
  });

  final int number;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: 'Page $number',
    child: InkWell(
      onTap: selected ? null : onPressed,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : null,
          borderRadius: BorderRadius.circular(2),
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
  });

  final String asset;
  final String tooltip;
  final VoidCallback? onPressed;

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
          padding: const EdgeInsets.all(5),
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
