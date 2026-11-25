import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../../core/widgets/row_menu.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/table_pagination.dart';
import '../../classification/domain/duplicate_detector.dart';
import '../../classification/presentation/classification_providers.dart';
import '../../map_view/presentation/report_map_panel.dart';
import '../data/models/damage_report.dart';
import 'report_providers.dart';
import 'widgets/report_archive.dart';
import 'widgets/report_filter_bar.dart';

/// Damage report management (Figma node `196:1371`).
///
/// Listed by priority, Critical first, the oldest first within each
/// (2026-11-26, [byPriorityThenOldest]); the campus map below it.
///
/// The shell — sidebar, top bar — comes from 2.A; this is the content
/// area only. Every number and row is read from Firestore; the mockup's
/// 42 / 12 / 4.2h / 08 and its four sample rows appear nowhere here.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: EdgeInsets.all(Breakpoints.gutter(context)),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(),
        SizedBox(height: PageHeader.gapBelow),
        _StatRow(),
        SizedBox(height: 32),
        ReportFilterBar(),
        _ReportsTableCard(),
        SizedBox(height: 32),
        // The campus map, whole: zoomed, panned, a pin opening its report
        // (2026-11-26; until then a still preview leading to Map View).
        ReportMapPanel(),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => PageHeader(
    title: 'Damage Reports',
    subtitle: 'Review and manage all incoming campus facility issues.',
    action: Tooltip(
      // Filing a report is a faculty/staff function (manuscript §1.5);
      // the admin console has no documented path for creating one.
      message:
          'Reports are submitted by faculty and staff from the mobile '
          'app — not from the admin console.',
      child: PageActionButton(
        label: 'Create Report',
        icon: SvgPicture.asset(
          'assets/icons/create_add.svg',
          width: 12,
          height: 12,
          colorFilter: const ColorFilter.mode(
            AppColors.textOnDark,
            BlendMode.srcIn,
          ),
        ),
        onPressed: null,
      ),
    ),
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
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 440
            ? 2
            : 1;
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
            emptyMessage: view.archived
                ? 'No archived reports. A closed, merged or rejected report '
                      'can be archived from its row or its page.'
                : view.hasFilters
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
          width: 150,
          cell: (report) => _ReportIdCell(report: report),
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
          width: 120,
          alignment: Alignment.centerRight,
          cell: _RowActions.new,
        ),
      ],
    );
  }
}

/// The report's number, with a mark when the duplicate rules flag it
/// (Objective 4.C) — so a duplicate is noticed in the table, not only on
/// its page.
class _ReportIdCell extends ConsumerWidget {
  const _ReportIdCell({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = switch (ref.watch(duplicateFlagsProvider)) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <String, List<DuplicateCandidate>>{},
    };
    final candidates = flags[report.id] ?? const <DuplicateCandidate>[];

    return Row(
      children: [
        Flexible(
          child: Text(
            DisplayId.report(report.id),
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.monoIdentifier.copyWith(
              color: AppColors.primary,
            ),
          ),
        ),
        if (candidates.isNotEmpty) ...[
          const SizedBox(width: 6),
          Tooltip(
            message:
                'Possible duplicate of '
                '${candidates.map((c) => DisplayId.report(c.report.id)).join(', ')}',
            child: Semantics(
              label: 'Possible duplicate',
              child: const Icon(
                Icons.content_copy_outlined,
                size: 16,
                color: AppColors.duplicateFlag,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// View, then one menu with what else the row can do.
///
/// The design (`196:1371`) drew View and four icons here: assign, edit,
/// merge and delete. Edit and merge were never functions of the console
/// (a submitted report is a record; merging duplicates has no objective
/// behind it), and sat greyed out on every row. Since 2026-11-15 (§34)
/// the two that are, Assign and Archive, are in the row's menu.
class _RowActions extends StatelessWidget {
  const _RowActions(this.report);

  final DamageReport report;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      RowViewButton(
        onPressed: () => context.go(RoutePaths.adminReportDetailFor(report.id)),
      ),
      const SizedBox(width: 4),
      _RowMenu(report),
    ],
  );
}

enum _RowAction { assign, archive }

class _RowMenu extends StatelessWidget {
  const _RowMenu(this.report);

  final DamageReport report;

  @override
  Widget build(BuildContext context) {
    final archivable = report.isArchived || report.canBeArchived;
    return RowMenuButton<_RowAction>(
      tooltip: 'Actions for ${DisplayId.report(report.id)}',
      onSelected: (action) => switch (action) {
        _RowAction.assign => context.go(
          RoutePaths.adminTaskAssignmentFor(report.id),
        ),
        _RowAction.archive => confirmReportArchive(context, report),
      },
      items: [
        // Offered once the report is approved and has no work order; until
        // the damage type and official priority are confirmed on its page
        // the repository would refuse, so the entry says so instead.
        if (report.awaitsAssignment)
          PopupMenuItem(
            value: _RowAction.assign,
            enabled: report.isAssignable,
            child: RowMenuEntry(
              'Assign',
              reason: report.isAssignable
                  ? null
                  : 'Confirm the damage type and official priority on the '
                        'report page first.',
            ),
          ),
        // The console's delete for a report (2026-11-08): reports are
        // archived, never deleted.
        PopupMenuItem(
          value: _RowAction.archive,
          enabled: archivable,
          child: RowMenuEntry(
            report.isArchived ? 'Restore from archive' : 'Archive',
            reason: archivable
                ? null
                : 'Only a closed, merged or rejected report can be archived.',
          ),
        ),
      ],
    );
  }
}
