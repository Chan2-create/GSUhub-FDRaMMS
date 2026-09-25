import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/damage_categories.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/category_chip.dart';
import '../analytics_summary.dart';

/// "Top Reported Issues This Month" (Figma `85:4169`): this calendar
/// month's reports grouped by kind of damage and building, busiest first.
///
/// The design's rows name free-text issues ("AC Unit Malfunction"); reports
/// carry a free-text title that cannot be grouped reliably, so "issue type"
/// is the damage category — the manuscript's own classification — and the
/// icon is that category's.
class TopIssuesTable extends StatelessWidget {
  const TopIssuesTable({required this.issues, super.key});

  final List<TopIssue> issues;

  /// Column shares, from the design's cell widths (105/258/218/117/174/99).
  static const List<int> _flex = [105, 258, 218, 117, 174, 99];

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        color: AppColors.surfaceMuted,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            _cell(0, const Text('RANK', style: AppTextStyles.kpiLabel)),
            _cell(1, const Text('ISSUE TYPE', style: AppTextStyles.kpiLabel)),
            _cell(2, const Text('BUILDING', style: AppTextStyles.kpiLabel)),
            _cell(
              3,
              const Text('REPORTS', style: AppTextStyles.kpiLabel),
              center: true,
            ),
            _cell(
              4,
              const Text('AVG RESOLUTION', style: AppTextStyles.kpiLabel),
            ),
            _cell(
              5,
              const Text('TREND', style: AppTextStyles.kpiLabel),
              center: true,
            ),
          ],
        ),
      ),
      if (issues.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Text(
            'No reports have been submitted this month yet.',
            style: AppTextStyles.bodySmall,
          ),
        )
      else
        for (var i = 0; i < issues.length; i++)
          _IssueRow(rank: i + 1, issue: issues[i]),
      Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.surfaceMuted,
          border: Border(top: BorderSide(color: AppColors.border)),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: TextButton(
          onPressed: () => context.go(RoutePaths.adminReports),
          child: const Text(
            'VIEW DETAILED REPORT',
            style: AppTextStyles.viewReportLink,
          ),
        ),
      ),
    ],
  );

  static Widget _cell(int column, Widget child, {bool center = false}) =>
      Expanded(
        flex: _flex[column],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: center ? Alignment.center : Alignment.centerLeft,
            child: child,
          ),
        ),
      );
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.rank, required this.issue});

  final int rank;
  final TopIssue issue;

  @override
  Widget build(BuildContext context) {
    final category = issue.category;
    final average = issue.averageResolutionDays;
    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          TopIssuesTable._cell(
            0,
            Text('#$rank', style: AppTextStyles.issueRank),
          ),
          TopIssuesTable._cell(
            1,
            Row(
              children: [
                _IssueIcon(category: category),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category?.label ?? 'Unclassified',
                    style: AppTextStyles.issueName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          TopIssuesTable._cell(
            2,
            Text(
              issue.facilityName,
              style: AppTextStyles.issueCell,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TopIssuesTable._cell(
            3,
            Text('${issue.count}', style: AppTextStyles.issueCount),
            center: true,
          ),
          TopIssuesTable._cell(
            4,
            Text(
              average == null
                  ? '—'
                  : '${average.toStringAsFixed(1)} Day${average == 1 ? '' : 's'}',
              style: AppTextStyles.issueCell,
            ),
          ),
          TopIssuesTable._cell(5, _TrendIcon(trend: issue.trend), center: true),
        ],
      ),
    );
  }
}

class _IssueIcon extends StatelessWidget {
  const _IssueIcon({required this.category});

  final DamageCategory? category;

  @override
  Widget build(BuildContext context) {
    final known = category;
    final CategoryColors colors = known == null
        ? (
            background: AppColors.statusNeutralBackground,
            foreground: AppColors.statusNeutralForeground,
          )
        : CategoryChip.colorsOf(known);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        known == null ? Icons.help_outline : CategoryChip.iconOf(known),
        size: 16,
        color: colors.foreground,
      ),
    );
  }
}

class _TrendIcon extends StatelessWidget {
  const _TrendIcon({required this.trend});

  final IssueTrend trend;

  @override
  Widget build(BuildContext context) {
    final (icon, color, meaning) = switch (trend) {
      IssueTrend.up => (
        Icons.arrow_upward,
        AppColors.trendUp,
        'More than last month',
      ),
      IssueTrend.flat => (
        Icons.remove,
        AppColors.trendFlat,
        'Same as last month',
      ),
      IssueTrend.down => (
        Icons.arrow_downward,
        AppColors.trendDown,
        'Fewer than last month',
      ),
    };
    return Tooltip(
      message: meaning,
      child: Icon(icon, size: 16, color: color),
    );
  }
}
