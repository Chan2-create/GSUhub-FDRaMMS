import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../enums/report_status.dart';
import '../enums/work_order_status.dart';

/// Coloured status pill used in the Recent Reports table and, later, the
/// damage-report and work-order screens.
///
/// Takes a typed enum rather than a string: the Shared Backend Contract
/// (1.A, rule 4) requires status to travel as `ReportStatus`, and a widget
/// that accepted a raw string would be the obvious place for that to leak.
class StatusChip extends StatelessWidget {
  const StatusChip._({
    required this.label,
    required this.background,
    required this.foreground,
  });

  /// Chip for a damage report's lifecycle status.
  factory StatusChip.report(ReportStatus status) {
    final (background, foreground) = _reportPalette(status);
    return StatusChip._(
      label: status.label,
      background: background,
      foreground: foreground,
    );
  }

  /// Chip for a work order's Kanban status.
  factory StatusChip.workOrder(WorkOrderStatus status) {
    final (background, foreground) = switch (status) {
      WorkOrderStatus.pending => (
        AppColors.statusPendingBackground,
        AppColors.statusPendingForeground,
      ),
      WorkOrderStatus.inProgress || WorkOrderStatus.forReview => (
        AppColors.statusInProgressBackground,
        AppColors.statusInProgressForeground,
      ),
      WorkOrderStatus.completed => (
        AppColors.statusResolvedBackground,
        AppColors.statusResolvedForeground,
      ),
    };
    return StatusChip._(
      label: status.label,
      background: background,
      foreground: foreground,
    );
  }

  final String label;
  final Color background;
  final Color foreground;

  /// The design shows only three chip treatments (red / blue / green), but
  /// `ReportStatus` has eleven values. They collapse by meaning: anything
  /// awaiting an administrator is "pending" red, anything actively moving
  /// is blue, anything finished is green, and the terminal
  /// merged/rejected/archived states are neutral grey — they are outcomes,
  /// not work.
  static (Color, Color) _reportPalette(ReportStatus status) => switch (status) {
    ReportStatus.submitted || ReportStatus.underReview => (
      AppColors.statusPendingBackground,
      AppColors.statusPendingForeground,
    ),
    ReportStatus.approved ||
    ReportStatus.assigned ||
    ReportStatus.inProgress ||
    ReportStatus.forReview => (
      AppColors.statusInProgressBackground,
      AppColors.statusInProgressForeground,
    ),
    ReportStatus.completed || ReportStatus.closed => (
      AppColors.statusResolvedBackground,
      AppColors.statusResolvedForeground,
    ),
    ReportStatus.merged || ReportStatus.rejected || ReportStatus.archived => (
      AppColors.statusNeutralBackground,
      AppColors.statusNeutralForeground,
    ),
  };

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(2),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        label,
        style: AppTextStyles.statusChip.copyWith(color: foreground),
      ),
    ),
  );
}
