import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/category_donut.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../reporting/data/models/damage_report.dart';
import 'dashboard_providers.dart';
import 'widgets/activity_feed.dart';
import 'widgets/building_volume_chart.dart';

/// Admin dashboard (Figma node `196:534`).
///
/// Every number here comes from Firestore through the 1.B repositories.
/// The mockup's values — 148, 42 Reports, #RP-2023-089, the 45/25/15/15
/// category split — are illustrative and appear nowhere in this code.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(25, 24, 48, 48),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Below ~1100px the side column would squeeze the table past
        // usability, so the layout stacks instead.
        final isWide = constraints.maxWidth >= 1100;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StatCardRow(),
            const SizedBox(height: 28),
            if (isWide)
              const IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _RecentReportsCard()),
                    SizedBox(width: 16),
                    SizedBox(width: 300, child: _SideColumn()),
                  ],
                ),
              )
            else
              const Column(
                children: [
                  _RecentReportsCard(),
                  SizedBox(height: 16),
                  _SideColumn(),
                ],
              ),
            const SizedBox(height: 16),
            const _VolumeCard(),
          ],
        );
      },
    ),
  );
}

class _SideColumn extends StatelessWidget {
  const _SideColumn();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [_CategoryCard(), SizedBox(height: 16), _ActivityCard()],
  );
}

class _StatCardRow extends ConsumerWidget {
  const _StatCardRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(dashboardCountsProvider);

    final isLoading = counts.isLoading;
    final resolved = counts.value?.fold((data) => data, (_) => null);
    final hasError = counts.hasError || (counts.value?.isFailure ?? false);

    final cards = [
      ('Total Reports', resolved?.total, AppColors.statAccentTotal),
      ('Needs Review', resolved?.needsReview, AppColors.statAccentNeedsReview),
      ('In Progress', resolved?.inProgress, AppColors.statAccentInProgress),
      ('Completed', resolved?.completed, AppColors.statAccentCompleted),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Four across on a desktop viewport, two-by-two when narrower.
        final columns = constraints.maxWidth >= 1000 ? 4 : 2;
        const gap = 18.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, value, accent) in cards)
              SizedBox(
                width: cardWidth,
                child: StatCard(
                  label: label,
                  value: value,
                  accent: accent,
                  isLoading: isLoading,
                  hasError: hasError,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RecentReportsCard extends ConsumerWidget {
  const _RecentReportsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
    title: 'Recent Reports',
    dividerUnderHeader: true,
    contentPadding: EdgeInsets.zero,
    trailing: Tooltip(
      message: 'The full report list arrives in Objective 2.B.',
      child: TextButton(
        onPressed: null,
        child: Text(
          'View All',
          style: AppTextStyles.buttonLabel.copyWith(color: AppColors.primary),
        ),
      ),
    ),
    child: AsyncValueView<List<DamageReport>>(
      value: ref.watch(recentReportsProvider),
      isEmpty: (reports) => reports.isEmpty,
      emptyMessage: 'No damage reports have been submitted yet.',
      emptyIcon: Icons.assignment_outlined,
      onRetry: () => refreshDashboard(ref),
      data: (reports) => AppDataTable<DamageReport>(
        rows: reports,
        columns: [
          AppTableColumn(
            label: 'Report ID',
            width: 140,
            cell: (report) =>
                Text(_shortId(report.id), style: AppTextStyles.monoIdentifier),
          ),
          AppTableColumn(
            label: 'Facility / Issue',
            flex: 2,
            cell: (report) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  report.title,
                  style: AppTextStyles.tableCellStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  categoryLabel(report.category),
                  style: AppTextStyles.tableCellCaption,
                ),
              ],
            ),
          ),
          AppTableColumn(
            label: 'Location',
            flex: 2,
            cell: (report) => Text(
              report.facilityName ?? report.locationDescription ?? '—',
              style: AppTextStyles.tableCell,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppTableColumn(
            label: 'Status',
            width: 130,
            cell: (report) => StatusChip.report(report.status),
          ),
          AppTableColumn(
            label: 'Actions',
            width: 90,
            alignment: Alignment.center,
            cell: (report) => Tooltip(
              message: 'Report detail arrives in Objective 2.B.',
              child: IconButton(
                onPressed: null,
                icon: SvgPicture.asset(
                  'assets/icons/action_view.svg',
                  width: 22,
                  height: 15,
                  colorFilter: const ColorFilter.mode(
                    AppColors.textFaint,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// Firestore ids are long and opaque; the table shows a short, stable
  /// prefix. The design's "#RP-2023-089" format implies a human-readable
  /// reference number, which the data model does not yet have — noted in
  /// the fidelity report.
  static String _shortId(String id) =>
      '#${id.length <= 8 ? id : id.substring(0, 8)}';
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
    title: 'Reports by Category',
    child: AsyncValueView<List<CategorySlice>>(
      value: ref.watch(reportsByCategoryProvider),
      isEmpty: (slices) => slices.isEmpty,
      emptyMessage: 'No reports to categorize yet.',
      emptyIcon: Icons.donut_large_outlined,
      onRetry: () => refreshDashboard(ref),
      data: (slices) => CategoryDonut(slices: slices),
    ),
  );
}

class _ActivityCard extends ConsumerWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
    title: 'Recent Activity',
    child: AsyncValueView(
      value: ref.watch(recentActivityProvider),
      isEmpty: (entries) => entries.isEmpty,
      emptyMessage: 'No recorded activity yet.',
      emptyIcon: Icons.history,
      onRetry: () => refreshDashboard(ref),
      data: (entries) => ActivityFeed(entries: entries),
    ),
  );
}

class _VolumeCard extends ConsumerWidget {
  const _VolumeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
    title: 'Monthly Report Volume by Building',
    subtitle:
        'Comparison of damage reports received across major university '
        'facilities.',
    trailing: const BuildingVolumeLegend(),
    contentPadding: const EdgeInsets.fromLTRB(33, 8, 33, 33),
    child: AsyncValueView<List<BuildingVolume>>(
      value: ref.watch(reportVolumeByBuildingProvider),
      isEmpty: (volumes) => volumes.isEmpty,
      emptyMessage: 'No reports recorded this month or last.',
      emptyIcon: Icons.bar_chart_outlined,
      onRetry: () => refreshDashboard(ref),
      data: (volumes) => BuildingVolumeChart(volumes: volumes),
    ),
  );
}
