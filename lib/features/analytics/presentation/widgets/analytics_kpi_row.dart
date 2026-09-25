import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/stat_card.dart';
import '../analytics_summary.dart';

/// TOTAL REPORTS, AVG RESOLUTION TIME, COMPLETION RATE, PENDING / OVERDUE
/// (Figma `85:3649`).
///
/// Each comparison is worded from the selected range — "vs last month" for
/// the default 30 days, as the design writes it, but "vs last week" for 7 —
/// so the footnote never claims a comparison the numbers did not make.
class AnalyticsKpiRow extends StatelessWidget {
  const AnalyticsKpiRow({required this.summary, super.key});

  final AsyncValue<Result<AnalyticsSummary>> summary;

  @override
  Widget build(BuildContext context) {
    final data = summary.value?.fold((s) => s, (_) => null);
    final isLoading = summary.isLoading;
    final hasError = summary.hasError || (summary.value?.isFailure ?? false);

    final cards = [
      _totalReports(data, isLoading, hasError),
      _resolution(data, isLoading, hasError),
      _completion(data, isLoading, hasError),
      _pending(data, isLoading, hasError),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 4 : 2;
        const gap = 24.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  static String? _comparedWith(AnalyticsSummary? data) =>
      data?.range.previousLabel;

  Widget _totalReports(AnalyticsSummary? data, bool isLoading, bool hasError) {
    final previous = data?.totalReportsPrevious;
    final current = data?.totalReports;
    final against = _comparedWith(data);

    StatTrend? trend;
    if (current != null && previous != null && (current > 0 || previous > 0)) {
      final delta = current - previous;
      trend = StatTrend(
        // A percentage of zero is undefined; say how many instead.
        text: previous == 0
            ? '+$current'
            : '${delta >= 0 ? '+' : '-'}'
                  '${(delta.abs() * 100 / previous).round()}%',
        isIncrease: delta >= 0,
        // Volume is information, not a verdict: more reports can mean more
        // damage or simply more people using the system. Shown in the
        // design's neutral-positive style either way.
        isFavourable: true,
      );
    }

    return StatCard.kpi(
      label: 'Total Reports',
      iconAsset: 'assets/icons/analytics_reports.svg',
      value: current,
      trend: trend,
      footnote: data == null
          ? null
          : (against == null ? 'all time' : 'vs $against'),
      definition: AnalyticsSummary.totalReportsDefinition,
      isLoading: isLoading,
      hasError: hasError,
    );
  }

  Widget _resolution(AnalyticsSummary? data, bool isLoading, bool hasError) {
    final current = data?.averageResolutionDays;
    final previous = data?.averageResolutionDaysPrevious;
    final against = _comparedWith(data);

    StatTrend? trend;
    String? footnote;
    if (data != null && current == null) {
      footnote = 'nothing completed in this period';
    } else if (current != null && previous != null && against != null) {
      final delta = double.parse((current - previous).toStringAsFixed(1));
      final sign = delta > 0 ? '+' : (delta < 0 ? '-' : '');
      trend = StatTrend(
        text: '$sign${delta.abs().toStringAsFixed(1)} days',
        isIncrease: delta > 0,
        isFavourable: delta <= 0,
      );
      footnote = delta < 0
          ? 'faster than $against'
          : delta > 0
          ? 'slower than $against'
          : 'same as $against';
    } else if (current != null && against != null) {
      footnote = 'nothing completed $against to compare';
    }

    return StatCard.kpi(
      label: 'Avg Resolution Time',
      iconAsset: 'assets/icons/analytics_resolution.svg',
      valueText: current?.toStringAsFixed(1),
      unit: 'days',
      trend: trend,
      footnote: footnote,
      definition: AnalyticsSummary.resolutionDefinition,
      isLoading: isLoading,
      hasError: hasError,
    );
  }

  Widget _completion(AnalyticsSummary? data, bool isLoading, bool hasError) {
    final current = data?.completionRate;
    final previous = data?.completionRatePrevious;

    StatTrend? trend;
    if (current != null && previous != null) {
      final points = ((current - previous) * 100).round();
      trend = StatTrend(
        text: '${points >= 0 ? '+' : '-'}${points.abs()}%',
        isIncrease: points >= 0,
        isFavourable: points >= 0,
      );
    }

    return StatCard.kpi(
      label: 'Completion Rate',
      iconAsset: 'assets/icons/analytics_completion.svg',
      valueText: current == null ? null : '${(current * 100).round()}%',
      trend: trend,
      progress: current ?? 0,
      definition: AnalyticsSummary.completionDefinition,
      isLoading: isLoading,
      hasError: hasError,
    );
  }

  Widget _pending(AnalyticsSummary? data, bool isLoading, bool hasError) {
    final current = data?.pendingOrOverdue;
    final previous = data?.pendingOrOverduePrevious;
    final against = _comparedWith(data);

    StatTrend? trend;
    String? footnote;
    if (current != null && previous != null && against != null) {
      final delta = current - previous;
      trend = StatTrend(
        text: delta == 0 ? '0' : '${delta > 0 ? '+' : '-'}${delta.abs()}',
        isIncrease: delta > 0,
        isFavourable: delta <= 0,
      );
      footnote = delta < 0
          ? 'fewer than $against'
          : delta > 0
          ? 'more than $against'
          : 'same as $against';
    }

    return StatCard.kpi(
      label: 'Pending / Overdue',
      iconAsset: 'assets/icons/analytics_pending.svg',
      value: current,
      trend: trend,
      footnote: footnote,
      // Red when there is something waiting, as the design draws it; a
      // zero is not a warning.
      valueColor: (current ?? 0) > 0 ? AppColors.error : null,
      definition: AnalyticsSummary.pendingDefinition,
      isLoading: isLoading,
      hasError: hasError,
    );
  }
}
