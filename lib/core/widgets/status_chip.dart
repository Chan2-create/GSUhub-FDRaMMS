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
    this.style = AppTextStyles.statusChip,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.radius = 2,
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

  /// Chip for a report in the faculty and staff app (Objective 3.A): its
  /// [ReportProgress] stage, white on the home screen's colours (Figma
  /// `170:2050`). [large] is My Reports' size (`169:1251`); the default is
  /// the home screen's.
  factory StatusChip.requestor(ReportStatus status, {bool large = false}) {
    final progress = status.progress;
    return StatusChip._(
      // A report that ended without work says how it ended.
      label: progress == ReportProgress.closedOut
          ? _sentenceCase(status.label)
          : progress.label,
      background: requestorColorOf(status),
      foreground: Colors.white,
      style: large
          ? AppTextStyles.requestorChipLarge
          : AppTextStyles.requestorChip,
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      radius: large ? 16 : 11,
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
  final TextStyle style;
  final EdgeInsets padding;
  final double radius;

  /// The faculty and staff app's colour for [status]'s stage — its chip,
  /// and the rule beside a report on the home screen.
  static Color requestorColorOf(ReportStatus status) =>
      switch (status.progress) {
        ReportProgress.pending => AppColors.progressPending,
        ReportProgress.inProgress => AppColors.progressInProgress,
        ReportProgress.completed => AppColors.progressCompleted,
        ReportProgress.closedOut => AppColors.statusNeutralForeground,
      };

  static String _sentenceCase(String text) =>
      text[0] + text.substring(1).toLowerCase();

  /// The design shows only three chip treatments (red / blue / green), but
  /// `ReportStatus` has eleven values. They collapse by meaning: anything
  /// awaiting an administrator is "pending" red, anything actively moving
  /// is blue, anything finished is green, and the terminal
  /// merged/rejected/archived states are neutral grey — they are outcomes,
  /// not work.
  static (Color, Color) _reportPalette(ReportStatus status) =>
      switch (status.progress) {
        ReportProgress.pending => (
          AppColors.statusPendingBackground,
          AppColors.statusPendingForeground,
        ),
        ReportProgress.inProgress => (
          AppColors.statusInProgressBackground,
          AppColors.statusInProgressForeground,
        ),
        ReportProgress.completed => (
          AppColors.statusResolvedBackground,
          AppColors.statusResolvedForeground,
        ),
        ReportProgress.closedOut => (
          AppColors.statusNeutralBackground,
          AppColors.statusNeutralForeground,
        ),
      };

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Padding(
      padding: padding,
      child: Text(label, style: style.copyWith(color: foreground)),
    ),
  );
}
