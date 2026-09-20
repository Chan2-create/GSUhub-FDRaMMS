import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/enums/report_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/table_pagination.dart';
import '../data/models/damage_report.dart';
import 'report_providers.dart';
import 'widgets/report_filter_bar.dart';
import 'widgets/report_side_panels.dart';

/// Damage report management (Figma node `196:1371`).
///
/// The shell — sidebar, top bar — comes from 2.A; this is the content
/// area only. Every number and row is read from Firestore; the mockup's
/// 42 / 12 / 4.2h / 08 and its four sample rows appear nowhere here.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: const EdgeInsets.all(32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(),
        const SizedBox(height: 24),
        const _StatRow(),
        const SizedBox(height: 48),
        const ReportFilterBar(),
        const _ReportsTableCard(),
        const SizedBox(height: 48),
        LayoutBuilder(
          builder: (context, constraints) {
            // The design puts the map beside the emergency card in a
            // three-column grid; below ~1000px they stack instead of
            // squeezing the map to an unreadable width.
            if (constraints.maxWidth < 1000) {
              return const Column(
                children: [
                  CampusViewCard(),
                  SizedBox(height: 24),
                  EmergencyCard(),
                ],
              );
            }
            return const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: CampusViewCard()),
                SizedBox(width: 24),
                Expanded(child: EmergencyCard()),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Damage Reports', style: AppTextStyles.pageTitle),
            SizedBox(height: 4),
            Text(
              'Review and manage all incoming campus facility issues.',
              style: AppTextStyles.pageSubtitle,
            ),
          ],
        ),
      ),
      Tooltip(
        // Filing a report is a faculty/staff function (manuscript §1.5);
        // the admin console has no documented path for creating one.
        message:
            'Reports are submitted by faculty and staff from the mobile '
            'app — not from the admin console.',
        child: FilledButton.icon(
          onPressed: null,
          icon: SvgPicture.asset(
            'assets/icons/create_add.svg',
            width: 12,
            height: 12,
            colorFilter: const ColorFilter.mode(
              AppColors.textOnDark,
              BlendMode.srcIn,
            ),
          ),
          label: const Text('Create Report', style: AppTextStyles.ctaLabel),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnDark,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    ],
  );
}

class _StatRow extends ConsumerWidget {
  const _StatRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(reportStatsProvider);
    final resolved = stats.value?.fold((data) => data, (_) => null);
    final isLoading = stats.isLoading;
    final hasError = stats.hasError || (stats.value?.isFailure ?? false);

    final cards = <Widget>[
      StatCard(
        label: 'TOTAL OPEN',
        value: resolved?.totalOpen,
        accent: AppColors.statAccentTotal,
        definition: 'Reports that are neither completed nor discarded.',
        isLoading: isLoading,
        hasError: hasError,
      ),
      StatCard(
        label: 'HIGH PRIORITY',
        value: resolved?.highPriority,
        accent: AppColors.statAccentNeedsReview,
        definition: 'Open reports at high or critical priority.',
        isLoading: isLoading,
        hasError: hasError,
      ),
      StatCard(
        label: 'AVG RESPONSE',
        valueText: resolved == null
            ? null
            : formatResponseTime(resolved.averageResponse),
        accent: AppColors.statAccentInProgress,
        definition: ReportStats.responseDefinition,
        isLoading: isLoading,
        hasError: hasError,
      ),
      StatCard(
        label: 'COMPLETED TODAY',
        value: resolved?.completedToday,
        accent: AppColors.statAccentCompleted,
        definition: 'Reports whose work order was completed today.',
        isLoading: isLoading,
        // A null count here means the work orders could not be read, which
        // is an error for this card even though the others are fine.
        hasError:
            hasError || (resolved != null && resolved.completedToday == null),
      ),
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
}

class _ReportsTableCard extends ConsumerWidget {
  const _ReportsTableCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(reportsViewProvider);
    final page = ref.watch(reportsPageProvider);
    final filtered = ref.watch(filteredReportsProvider);
    final total =
        filtered.value?.fold((reports) => reports.length, (_) => 0) ?? 0;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          left: BorderSide(color: AppColors.borderStrong),
          right: BorderSide(color: AppColors.borderStrong),
          bottom: BorderSide(color: AppColors.borderStrong),
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Column(
        children: [
          AsyncValueView<List<DamageReport>>(
            value: page,
            isEmpty: (reports) => reports.isEmpty,
            emptyMessage: view.hasFilters
                ? 'No reports match these filters.'
                : 'No damage reports have been submitted yet.',
            onRetry: () => ref.invalidate(reportsStreamProvider),
            data: (reports) => _ReportsTable(reports: reports),
          ),
          if (total > 0)
            TablePagination(
              page: view.page,
              pageSize: ReportsView.pageSize,
              totalItems: total,
              onPageChanged: ref.read(reportsViewProvider.notifier).setPage,
            ),
        ],
      ),
    );
  }
}

class _ReportsTable extends StatelessWidget {
  const _ReportsTable({required this.reports});

  final List<DamageReport> reports;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, y');

    return AppDataTable<DamageReport>(
      rows: reports,
      columns: [
        AppTableColumn(
          label: 'Report ID',
          width: 130,
          cell: (report) => Text(
            DisplayId.report(report.id),
            style: AppTextStyles.monoIdentifier.copyWith(
              color: AppColors.primary,
            ),
          ),
        ),
        AppTableColumn(
          label: 'Reporter',
          cell: (report) =>
              Text(report.reporterName, style: AppTextStyles.tableCell),
        ),
        AppTableColumn(
          label: 'Damage Type',
          cell: (report) => Text(
            report.category?.label ?? 'Unclassified',
            style: AppTextStyles.tableCell,
          ),
        ),
        AppTableColumn(
          label: 'Location',
          cell: (report) => Text(
            report.facilityName ?? report.locationDescription ?? '—',
            style: AppTextStyles.tableCell,
          ),
        ),
        AppTableColumn(
          label: 'Priority',
          width: 130,
          cell: (report) => PriorityChip(
            level: report.effectivePriority,
            confirmed: report.isPriorityConfirmed,
          ),
        ),
        AppTableColumn(
          label: 'Status',
          width: 150,
          cell: (report) => StatusChip.report(report.status),
        ),
        AppTableColumn(
          label: 'Date Submitted',
          width: 130,
          cell: (report) => Text(
            dateFormat.format(report.submittedAt.toLocal()),
            style: AppTextStyles.tableCell,
          ),
        ),
        const AppTableColumn(
          label: 'Actions',
          width: 190,
          alignment: Alignment.centerRight,
          cell: _RowActions.new,
        ),
      ],
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions(this.report);

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    final canAssign =
        report.status == ReportStatus.approved && report.workOrderId == null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: () =>
              context.go(RoutePaths.adminReportDetailFor(report.id)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accentOlive,
            side: const BorderSide(color: AppColors.accentOlive),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          child: const Text('View', style: AppTextStyles.rowActionText),
        ),
        const SizedBox(width: 4),
        _IconAction(
          asset: 'assets/icons/action_assign.svg',
          width: 18.33,
          height: 13.33,
          tooltip: canAssign
              ? 'Assign this report'
              : 'Only an approved report that has no work order can be '
                    'assigned.',
          onPressed: canAssign
              ? () => context.go(RoutePaths.adminTaskAssignmentFor(report.id))
              : null,
        ),
        const _IconAction(
          asset: 'assets/icons/action_edit.svg',
          width: 15,
          height: 15,
          // Editing a submitted report is not in the manuscript's admin
          // functions: a report is a record, and corrections go through
          // GSU rather than being silently rewritten.
          tooltip: 'Editing a submitted report is not an admin function.',
          onPressed: null,
        ),
        const _IconAction(
          asset: 'assets/icons/action_merge.svg',
          width: 10,
          height: 14.17,
          // The glyph is Material's "merge" — this row action was drawn
          // for merging duplicate reports, which has repository support
          // from 1.B but no objective that surfaces it. See the report.
          tooltip: 'Merging duplicate reports is not in the current WBS.',
          onPressed: null,
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.asset,
    required this.width,
    required this.height,
    required this.tooltip,
    required this.onPressed,
  });

  final String asset;
  final double width;
  final double height;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    // A plain sized target rather than IconButton: four controls share a
    // fixed-width cell, and IconButton adds padding of its own that
    // overflows it.
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: SvgPicture.asset(
            asset,
            width: width,
            height: height,
            colorFilter: ColorFilter.mode(
              onPressed == null ? AppColors.textFaint : AppColors.iconMuted,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    ),
  );
}
