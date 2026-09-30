import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/category_donut.dart';
import '../../../core/widgets/section_card.dart';
import '../../reporting/presentation/report_providers.dart';
import '../../work_orders/presentation/work_order_providers.dart';
import 'analytics_providers.dart';
import 'analytics_summary.dart';
import 'widgets/analytics_kpi_row.dart';
import 'widgets/building_bars.dart';
import 'widgets/monthly_volume_chart.dart';
import 'widgets/resolution_trend_chart.dart';
import 'widgets/top_issues_table.dart';

/// Maintenance analytics (Figma node `61:5086`, content area only).
///
/// Every figure is computed from the live report and work-order feeds for
/// the period chosen in the top bar; nothing on this page is stored. The
/// mockup's 148 / 3.2 / 87% / 6 and its sample rows appear nowhere here.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  static const double _gap = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(analyticsSummaryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Analytics', style: AppTextStyles.pageTitle),
          const SizedBox(height: 32),
          AnalyticsKpiRow(summary: summary),
          const SizedBox(height: 24),
          // The design sets the charts on a tinted panel of their own.
          ColoredBox(
            color: AppColors.surfaceSunken,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: AsyncValueView<AnalyticsSummary>(
                value: summary,
                loadingHeight: 480,
                onRetry: () => ref
                  ..invalidate(reportsStreamProvider)
                  ..invalidate(workOrdersStreamProvider),
                data: (data) => _Charts(summary: data),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Charts extends StatelessWidget {
  const _Charts({required this.summary});

  final AnalyticsSummary summary;

  static const EdgeInsets _header = EdgeInsets.fromLTRB(25, 25, 25, 0);
  static const EdgeInsets _body = EdgeInsets.fromLTRB(25, 24, 25, 25);

  @override
  Widget build(BuildContext context) {
    final badge = ResolutionTrendChart.badgeFor(summary.resolutionByMonth);
    final period = summary.range.label.toLowerCase();

    final monthly = SectionCard(
      title: 'Monthly Report Volume',
      titleStyle: AppTextStyles.chartTitle,
      headerPadding: _header,
      contentPadding: _body,
      child: MonthlyVolumeChart(months: summary.monthlyVolume),
    );
    final byType = SectionCard(
      title: 'Reports by Damage Type',
      titleStyle: AppTextStyles.chartTitle,
      headerPadding: _header,
      contentPadding: _body,
      child: summary.byCategory.isEmpty
          ? _Empty('No reports in the $period.')
          : CategoryDonut.besideLegend(slices: summary.byCategory),
    );
    final byBuilding = SectionCard(
      title: 'Reports by Building',
      titleStyle: AppTextStyles.chartTitle,
      headerPadding: _header,
      contentPadding: _body,
      child: summary.byBuilding.isEmpty
          ? _Empty('No reports in the $period.')
          : BuildingBars(buildings: summary.byBuilding),
    );
    final resolution = SectionCard(
      title: 'Average Resolution Time by Month',
      titleStyle: AppTextStyles.chartTitle,
      headerPadding: _header,
      contentPadding: _body,
      trailing: badge == null
          ? null
          : ResolutionBadge(text: badge.text, improved: badge.improved),
      child: summary.resolutionByMonth.every((m) => m.value == null)
          ? const _Empty('No work orders completed in the last six months.')
          : ResolutionTrendChart(months: summary.resolutionByMonth),
    );
    final issues = SectionCard(
      title: 'Top Reported Issues This Month',
      titleStyle: AppTextStyles.chartTitle,
      headerPadding: const EdgeInsets.all(24),
      headerColor: AppColors.tableTitleBar,
      dividerUnderHeader: true,
      contentPadding: EdgeInsets.zero,
      child: TopIssuesTable(issues: summary.topIssues),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoUp = constraints.maxWidth >= 900;
        Widget pair(Widget left, Widget right) => twoUp
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: AnalyticsScreen._gap),
                    Expanded(child: right),
                  ],
                ),
              )
            : Column(
                children: [
                  left,
                  const SizedBox(height: AnalyticsScreen._gap),
                  right,
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            pair(monthly, byType),
            const SizedBox(height: 32),
            pair(byBuilding, resolution),
            const SizedBox(height: 32),
            issues,
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 160,
    child: Center(child: Text(message, style: AppTextStyles.bodySmall)),
  );
}
