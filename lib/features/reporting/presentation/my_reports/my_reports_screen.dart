import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shells/requestor/requestor_shell.dart';
import '../../../../shells/requestor/requestor_title_row.dart';
import '../../data/models/damage_report.dart';
import 'my_reports_providers.dart';
import 'widgets/report_pills.dart';

/// My Reports — the signed-in requestor's own reports, searchable and
/// filtered by stage (Figma `169:1251`, Objective 3.A).
///
/// Only their own: the query asks for the requestor's reports, and the
/// security rules refuse anything else. Live (3.B): a status change moves a
/// card between filters without a refresh. A card opens its detail page.
class MyReportsScreen extends ConsumerWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(myReportsProvider);
    final view = ref.watch(myReportsViewProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RequestorTitleRow(
          title: 'Reports',
          onBack: () => context.go(RoutePaths.staffHome),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              24,
              22,
              24,
              requestorBottomInset(context),
            ),
            children: [
              _SearchBox(
                initial: view.search,
                onChanged: ref.read(myReportsViewProvider.notifier).setSearch,
              ),
              const SizedBox(height: 16),
              _Filters(
                selected: view.progress,
                onSelected: ref
                    .read(myReportsViewProvider.notifier)
                    .setProgress,
              ),
              const SizedBox(height: 24),
              AsyncValueView<List<DamageReport>>(
                value: reports,
                isEmpty: (list) => list.isEmpty,
                emptyIcon: Icons.assignment_outlined,
                emptyMessage:
                    'You have not filed any reports yet. Tap + to report '
                    'facility damage.',
                onRetry: () => ref.invalidate(myReportsProvider),
                data: (list) {
                  final shown = list.where(view.matches).toList();
                  if (shown.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No reports match your search or filter.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.placeholderBody,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final report in shown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _ReportCard(report: report),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Search your reports..." on sand, with a gold magnifier (`169:842`).
class _SearchBox extends StatefulWidget {
  const _SearchBox({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(
      color: AppColors.warmFill,
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.only(left: 8, right: 4),
    child: Row(
      children: [
        const Icon(Icons.search, color: AppColors.accentGold, size: 22),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _controller,
            onChanged: widget.onChanged,
            textInputAction: TextInputAction.search,
            style: AppTextStyles.myReportsSearch,
            decoration: InputDecoration(
              hintText: 'Search your reports...',
              hintStyle: AppTextStyles.myReportsSearch.copyWith(
                color: AppColors.searchPlaceholder,
              ),
              border: InputBorder.none,
              isCollapsed: true,
            ),
          ),
        ),
      ],
    ),
  );
}

/// All · Pending · In Progress · Completed (`169:847`), scrolling sideways
/// as drawn.
///
/// The selected filter is filled — gold for All, as drawn, and the stage's
/// own colour otherwise. The others are outlined in neutral grey: the
/// home screen's yellow, which these stages now share, cannot carry text
/// on this background.
class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelected});

  final ReportProgress? selected;
  final ValueChanged<ReportProgress?> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: Row(
      children: [
        _FilterChip(
          label: 'All',
          color: AppColors.accentGold,
          selected: selected == null,
          onTap: () => onSelected(null),
        ),
        for (final progress in MyReportsView.filters) ...[
          const SizedBox(width: 8),
          _FilterChip(
            label: progress.label,
            color: switch (progress) {
              ReportProgress.pending => AppColors.progressPending,
              ReportProgress.inProgress => AppColors.progressInProgress,
              ReportProgress.completed ||
              ReportProgress.closedOut => AppColors.progressCompleted,
            },
            selected: selected == progress,
            onTap: () => onSelected(progress),
          ),
        ],
      ],
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? color : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? color : AppColors.warmMuted,
          width: 1.5,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
          child: Text(
            label,
            style: AppTextStyles.myReportsFilter.copyWith(
              color: selected ? Colors.white : AppColors.warmText,
            ),
          ),
        ),
      ),
    ),
  );
}

/// One report (`169:857`): where it is, its damage type and stage, when it
/// was filed, and a gold rule down its left edge. Opens the report.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final DamageReport report;

  static final DateFormat _date = DateFormat('MMM d, y');

  @override
  Widget build(BuildContext context) {
    final category = shownCategoryOf(report);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        onTap: () => context.push(RoutePaths.staffReportDetailFor(report.id)),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: AppColors.accentGold, width: 4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reportPlaceOf(report),
                        style: AppTextStyles.myReportsLocation,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (category != null)
                            MyReportsCategoryPill(category: category),
                          StatusChip.requestor(report.status, large: true),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Submitted: '
                        '${_date.format(report.submittedAt.toLocal())}',
                        style: AppTextStyles.myReportsSubmitted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.accentGold,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
