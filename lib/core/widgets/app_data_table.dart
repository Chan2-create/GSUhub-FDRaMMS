import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import 'scroll_when_narrow.dart';

/// One column in an [AppDataTable].
class AppTableColumn<T> {
  const AppTableColumn({
    required this.label,
    required this.cell,
    this.flex = 1,
    this.width,
    this.alignment = Alignment.centerLeft,
  });

  /// Header text. Rendered uppercase with the design's tracking.
  final String label;

  /// Builds the cell for one row.
  final Widget Function(T row) cell;

  /// Share of the remaining width, when [width] is null.
  final int flex;

  /// Fixed width, for columns that should not stretch (identifiers,
  /// action buttons).
  final double? width;

  final Alignment alignment;
}

/// Bordered table matching the dashboard's Recent Reports styling
/// (Figma `196:661`).
///
/// Built on Row/Column rather than Flutter's `DataTable`: the design needs
/// two-line cells with a caption beneath the primary text, per-row
/// heights that follow content, and a chip column — all of which fight
/// `DataTable`'s fixed row model.
///
/// Empty and error states are the caller's responsibility via
/// `AsyncValueView`; this renders rows it is given.
///
/// Narrower than its columns need (a tablet or a phone), the table keeps
/// its columns and scrolls sideways inside its card, so no cell is
/// clipped and the page itself never scrolls sideways.
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    required this.columns,
    required this.rows,
    super.key,
    this.rowPadding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    this.scrollable = true,
  });

  final List<AppTableColumn<T>> columns;
  final List<T> rows;
  final EdgeInsets rowPadding;

  /// False where the table always has its room and sits in an
  /// IntrinsicHeight (the dashboard's wide layout): measuring the room,
  /// to scroll when narrow, cannot report an intrinsic height.
  final bool scrollable;

  /// The least a stretching column is given (per unit of flex) before the
  /// table scrolls. Small enough that every table fits as drawn at the
  /// design's 1440 width.
  static const double minFlexibleWidth = 64;

  double get _minWidth =>
      rowPadding.horizontal +
      columns.fold<double>(
        0,
        (sum, column) => sum + (column.width ?? minFlexibleWidth * column.flex),
      );

  @override
  Widget build(BuildContext context) {
    final table = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        for (var i = 0; i < rows.length; i++) _row(rows[i], isFirst: i == 0),
      ],
    );
    return scrollable
        ? ScrollWhenNarrow(minWidth: _minWidth, child: table)
        : table;
  }

  Widget _header() => Container(
    decoration: const BoxDecoration(
      color: AppColors.surfaceMuted,
      border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
    child: Row(
      children: [
        for (final column in columns)
          _sized(
            column,
            Align(
              alignment: column.alignment,
              child: Text(
                column.label.toUpperCase(),
                style: AppTextStyles.tableHeader,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _row(T row, {required bool isFirst}) => Container(
    decoration: BoxDecoration(
      border: isFirst
          ? null
          : const Border(top: BorderSide(color: AppColors.borderSubtle)),
    ),
    padding: rowPadding,
    child: Row(
      children: [
        for (final column in columns)
          _sized(
            column,
            Align(alignment: column.alignment, child: column.cell(row)),
          ),
      ],
    ),
  );

  Widget _sized(AppTableColumn<T> column, Widget child) => column.width != null
      ? SizedBox(width: column.width, child: child)
      : Expanded(flex: column.flex, child: child);
}
