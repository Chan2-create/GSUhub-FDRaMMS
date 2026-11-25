import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/constants/damage_categories.dart';
import '../../../core/enums/account_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../damage_reports/data/models/damage_report.dart';
import '../../damage_reports/presentation/report_providers.dart';
import '../../user_management/data/models/app_user.dart';
import '../../user_management/presentation/personnel_providers.dart';
import 'assignment_controller.dart';
import 'widgets/personnel_assignment.dart';

/// Task Assignment (Figma node `61:4970`, content area only).
///
/// Left: reports that passed review and have no work order yet. Right: who
/// can take them. Picking a report on the left enables the Assign buttons
/// on the right — the design shows both panels live at once, and an assign
/// action needs both halves.
///
/// Since 2026-11-26 a report is assigned on its own page, straight after
/// its approval; this screen stays for assigning from the queue and for
/// looking over who holds what. Both use the same pieces
/// (widgets/personnel_assignment.dart), and with a report picked the panel
/// lists its trade only (Table 3.3), as the report page does.
class TaskAssignmentScreen extends ConsumerStatefulWidget {
  const TaskAssignmentScreen({super.key, this.preselectedReportId});

  /// Set when arriving from the assign action on a row of the reports
  /// table, so the administrator does not have to find the report again.
  final String? preselectedReportId;

  @override
  ConsumerState<TaskAssignmentScreen> createState() =>
      _TaskAssignmentScreenState();
}

class _TaskAssignmentScreenState extends ConsumerState<TaskAssignmentScreen> {
  @override
  void initState() {
    super.initState();
    final preselected = widget.preselectedReportId;
    if (preselected != null) {
      // After the first frame: selecting during build would write to a
      // provider while the widget tree is still being built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(selectedReportProvider.notifier).select(preselected);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(Breakpoints.gutter(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Task Assignment',
          subtitle: 'Assign validated reports to maintenance personnel.',
        ),
        const SizedBox(height: PageHeader.gapBelow),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 1000) {
              return const Column(
                children: [
                  _UnassignedQueue(),
                  SizedBox(height: 32),
                  _PersonnelPanel(),
                ],
              );
            }
            // The design's 12-column grid: the queue on 5, the panel on 7.
            return const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _UnassignedQueue()),
                SizedBox(width: 32),
                Expanded(flex: 7, child: _PersonnelPanel()),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _UnassignedQueue extends ConsumerWidget {
  const _UnassignedQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(unassignedReportsProvider);
    final pending =
        reports.value?.fold((list) => list.length, (_) => null) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'UNASSIGNED REPORTS',
                style: AppTextStyles.sectionOverline,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.statusInProgressBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$pending PENDING',
                style: AppTextStyles.badgeText.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncValueView<List<DamageReport>>(
          value: reports,
          isEmpty: (list) => list.isEmpty,
          emptyIcon: Icons.task_alt_outlined,
          emptyMessage:
              'No reports are waiting for assignment. Reports appear here '
              'once they have been approved.',
          onRetry: () => ref.invalidate(reportsStreamProvider),
          data: (list) => Column(
            children: [
              for (final report in list) ...[
                _QueueCard(report: report),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _QueueCard extends ConsumerWidget {
  const _QueueCard({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = ref.watch(selectedReportProvider) == report.id;
    // The repository will not raise a work order without a category — it
    // routes the job to a trade — or without a confirmed official priority
    // (Objective 4.C), so the card says so here rather than letting an
    // administrator choose a technician and then fail.
    final needsReview = !report.isAssignable;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      // The design marks the card being acted on with a thick left edge.
      // Drawn as a clipped strip rather than a thicker BorderSide: a
      // border whose sides differ in colour cannot carry a borderRadius,
      // and Flutter throws at paint time if it does.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // IntrinsicHeight so the accent strip runs the full height of the
        // card, which is sized by its content.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isSelected)
                Container(width: 4, color: AppColors.cardSelectedAccent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(21),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DisplayId.report(report.id),
                                  style: AppTextStyles.queueCardId,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  report.title,
                                  style: AppTextStyles.queueCardTitle,
                                ),
                              ],
                            ),
                          ),
                          PriorityChip(
                            level: report.effectivePriority,
                            confirmed: report.isPriorityConfirmed,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SvgPicture.asset(
                            'assets/icons/location_pin.svg',
                            width: 9.33,
                            height: 11.67,
                            colorFilter: const ColorFilter.mode(
                              AppColors.textMuted,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              report.facilityName ??
                                  report.locationDescription ??
                                  '—',
                              style: AppTextStyles.metaText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: _SelectButton(
                          needsReview: needsReview,
                          reportId: report.id,
                          isSelected: isSelected,
                          onPressed: () => ref
                              .read(selectedReportProvider.notifier)
                              .select(isSelected ? null : report.id),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The queue card's own button: picks the report, or explains why it
/// cannot be picked.
class _SelectButton extends StatelessWidget {
  const _SelectButton({
    required this.needsReview,
    required this.reportId,
    required this.isSelected,
    required this.onPressed,
  });

  final bool needsReview;
  final String reportId;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // A report not yet reviewed opens its page, where the type and
    // priority are set (4.C), rather than sitting there disabled.
    final button = FilledButton(
      onPressed: needsReview
          ? () => context.go(RoutePaths.adminReportDetailFor(reportId))
          : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: isSelected
            ? AppColors.sidebarBackground
            : AppColors.primary,
        foregroundColor: AppColors.textOnDark,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(switch ((needsReview, isSelected)) {
        (true, _) => 'Review type and priority',
        (false, true) => 'Selected — choose personnel',
        (false, false) => 'Assign',
      }, style: AppTextStyles.metaText.copyWith(color: AppColors.textOnDark)),
    );

    // Only wrapped when there is something to say: a Tooltip with an
    // empty message still opens an empty bubble on hover.
    if (!needsReview) return button;
    return Tooltip(
      message:
          'The damage type and official priority are confirmed on the '
          'report page before the work is assigned.',
      child: button,
    );
  }
}

class _PersonnelPanel extends ConsumerStatefulWidget {
  const _PersonnelPanel();

  @override
  ConsumerState<_PersonnelPanel> createState() => _PersonnelPanelState();
}

class _PersonnelPanelState extends ConsumerState<_PersonnelPanel> {
  DamageCategory? _tradeFilter;

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedReportProvider);
    final selected = ref
        .watch(unassignedReportsProvider)
        .value
        ?.fold(
          (reports) =>
              reports.where((report) => report.id == selectedId).firstOrNull,
          (_) => null,
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 17),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Personnel Availability',
                    style: AppTextStyles.panelTitle,
                  ),
                ),
                PopupMenuButton<DamageCategory?>(
                  tooltip: 'Filter by trade',
                  position: PopupMenuPosition.under,
                  initialValue: _tradeFilter,
                  onSelected: (value) => setState(() => _tradeFilter = value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(child: Text('All trades')),
                    for (final category in DamageCategory.values)
                      PopupMenuItem(
                        value: category,
                        child: Text(category.assignedPersonnelLabel),
                      ),
                  ],
                  child: SvgPicture.asset(
                    'assets/icons/filter_list.svg',
                    width: 18,
                    height: 12,
                    colorFilter: ColorFilter.mode(
                      _tradeFilter == null
                          ? AppColors.textFaint
                          : AppColors.primary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: AsyncValueView<List<AppUser>>(
              value: ref.watch(personnelStreamProvider),
              isEmpty: (people) => people.isEmpty,
              emptyIcon: Icons.people_outline,
              emptyMessage: 'No maintenance personnel accounts exist yet.',
              onRetry: () => ref.invalidate(personnelStreamProvider),
              data: (people) {
                // A report picked: its trade only (Table 3.3), as on the
                // report's page. None picked: everyone, or the trade the
                // filter names.
                final category = selected?.category;
                final trade = category ?? _tradeFilter;
                final ranked = category != null
                    ? personnelOfTrade(people, category)
                    : trade == null
                    ? rankedForCategory(people, null)
                    : personnelOfTrade(people, trade);

                if (ranked.isEmpty) {
                  return Text(
                    trade == null
                        ? 'No personnel match this trade.'
                        : 'No ${trade.assignedPersonnelLabel} accounts. '
                              'When nobody can take the work, reschedule '
                              'the report on its page.',
                    style: AppTextStyles.bodySmall,
                  );
                }

                return Column(
                  children: [
                    const _PersonnelHeaderRow(),
                    for (final person in ranked)
                      _PersonnelRow(person: person, report: selected),
                  ],
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                onPressed: () => context.go(RoutePaths.adminPersonnel),
                child: Text(
                  'View All Personnel',
                  style: AppTextStyles.badgeText.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonnelRow extends ConsumerStatefulWidget {
  const _PersonnelRow({required this.person, required this.report});

  final AppUser person;

  /// The report selected for assignment, or null when none is.
  final DamageReport? report;

  @override
  ConsumerState<_PersonnelRow> createState() => _PersonnelRowState();
}

class _PersonnelRowState extends ConsumerState<_PersonnelRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final report = widget.report;
    final isActive = person.accountStatus == AccountStatus.active;
    final canAssign = isActive && report != null && !_busy;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          PersonAvatar(fullName: person.fullName, isActive: isActive),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.fullName, style: AppTextStyles.personName),
                Text(
                  person.specialization?.assignedPersonnelLabel ??
                      'No trade recorded',
                  style: AppTextStyles.personRole,
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${person.activeTaskCount} active',
              style: AppTextStyles.taskCount.copyWith(
                color: isActive ? null : AppColors.textFaint,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.presenceActive
                        : AppColors.presenceInactive,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isActive ? 'ACTIVE' : 'INACTIVE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.presenceLabel.copyWith(
                      color: isActive
                          ? AppColors.presenceActiveText
                          : AppColors.textFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _actionColumnWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: !isActive
                    ? 'This account is inactive and cannot take work.'
                    : report == null
                    ? 'Select a report on the left first.'
                    : 'Assign ${report.title} to ${person.fullName}',
                child: OutlinedButton(
                  onPressed: canAssign ? _assign : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                      color: canAssign ? AppColors.primary : AppColors.border,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Assign',
                    style: AppTextStyles.outlineButtonSmall,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The same confirmation and call as the report's own page.
  Future<void> _assign() async {
    final report = widget.report;
    if (report == null) return;
    await assignReportTo(
      context,
      ref,
      report,
      widget.person,
      onConfirmed: () {
        if (mounted) setState(() => _busy = true);
      },
    );
    if (mounted) setState(() => _busy = false);
  }
}

/// Column headers over the personnel rows (Figma `76:2711`).
class _PersonnelHeaderRow extends StatelessWidget {
  const _PersonnelHeaderRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        // Clears the avatar so the headings sit over their columns.
        SizedBox(width: 52),
        Expanded(
          flex: 3,
          child: Text('Name', style: AppTextStyles.panelHeaderCell),
        ),
        Expanded(
          child: Text('Current Tasks', style: AppTextStyles.panelHeaderCell),
        ),
        Expanded(child: Text('Status', style: AppTextStyles.panelHeaderCell)),
        SizedBox(
          width: _actionColumnWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('Action', style: AppTextStyles.panelHeaderCell),
          ),
        ),
      ],
    ),
  );
}

/// Shared by the header and the rows so the Action column lines up.
const double _actionColumnWidth = 104;
