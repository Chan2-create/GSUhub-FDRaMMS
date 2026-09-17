import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

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
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    required this.columns,
    required this.rows,
    super.key,
    this.rowPadding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  final List<AppTableColumn<T>> columns;
  final List<T> rows;
  final EdgeInsets rowPadding;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _header(),
      for (var i = 0; i < rows.length; i++) _row(rows[i], isFirst: i == 0),
    ],
  );

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
