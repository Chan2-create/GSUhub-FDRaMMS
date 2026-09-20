import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/damage_categories.dart';
import '../../../core/enums/account_status.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/initials.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../reporting/presentation/report_providers.dart';
import '../../user_management/data/models/app_user.dart';
import '../../user_management/presentation/personnel_providers.dart';
import 'assignment_controller.dart';

/// Task Assignment (Figma node `61:4970`, content area only).
///
/// Left: reports that passed review and have no work order yet. Right: who
/// can take them. Picking a report on the left enables the Assign buttons
/// on the right — the design shows both panels live at once, and an assign
/// action needs both halves.
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
    padding: const EdgeInsets.all(32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Task Assignment', style: AppTextStyles.pageTitle),
        const SizedBox(height: 4),
        const Text(
          'Assign validated reports to maintenance personnel',
          style: AppTextStyles.pageSubtitle,
        ),
        const SizedBox(height: 32),
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
    // is what routes the job to a trade — so the card says so here rather
    // than letting an administrator choose a technician and then fail.
    final needsCategory = !report.isAssignable;

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
                          needsCategory: needsCategory,
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
    required this.needsCategory,
    required this.isSelected,
    required this.onPressed,
  });

  final bool needsCategory;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: needsCategory ? null : onPressed,
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
      child: Text(
        switch ((needsCategory, isSelected)) {
          (true, _) => 'Needs classification',
          (false, true) => 'Selected — choose personnel',
          (false, false) => 'Assign',
        },
        style: AppTextStyles.metaText.copyWith(
          color: needsCategory ? AppColors.textSecondary : AppColors.textOnDark,
        ),
      ),
    );

    // Only wrapped when there is something to say: a Tooltip with an
    // empty message still opens an empty bubble on hover.
    if (!needsCategory) return button;
    return Tooltip(
      message:
          'This report has no damage category yet, so there is no trade to '
          'route it to. Classifying is Objective 4.C.',
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
                final visible = _tradeFilter == null
                    ? people
                    : people
                          .where(
                            (person) =>
                                person.specialization?.assignedPersonnelLabel ==
                                _tradeFilter!.assignedPersonnelLabel,
                          )
                          .toList();

                // Ranked against the selected report's trade, so the right
                // people surface first without anyone being hidden.
                final ranked = rankedForCategory(visible, selected?.category);

                if (ranked.isEmpty) {
                  return const Text(
                    'No personnel match this trade.',
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
              child: Tooltip(
                message: 'The personnel directory arrives in Objective 2.C.',
                child: TextButton(
                  onPressed: null,
                  child: Text(
                    'View All Personnel',
                    style: AppTextStyles.badgeText.copyWith(
                      color: AppColors.textFaint,
                    ),
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
          _Avatar(person: person, isActive: isActive),
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
                Text(
                  isActive ? 'ACTIVE' : 'INACTIVE',
                  style: AppTextStyles.presenceLabel.copyWith(
                    color: isActive
                        ? AppColors.presenceActiveText
                        : AppColors.textFaint,
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

  Future<void> _assign() async {
    final report = widget.report;
    if (report == null) return;

    final confirmation = await showDialog<_AssignmentChoice>(
      context: context,
      builder: (_) => _AssignDialog(report: report, person: widget.person),
    );
    if (confirmation == null || !mounted) return;

    setState(() => _busy = true);
    final result = await ref
        .read(assignmentControllerProvider)
        .assign(
          reportId: report.id,
          personnelId: widget.person.id,
          targetCompletion: confirmation.targetCompletion,
        );
    if (!mounted) return;
    setState(() => _busy = false);

    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (_) => messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${report.title} assigned to ${widget.person.fullName}.',
          ),
        ),
      ),
      (failure) => messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      ),
    );
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.person, required this.isActive});

  final AppUser person;
  final bool isActive;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: isActive ? AppColors.avatarBackground : AppColors.borderSubtle,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      initialsOf(person.fullName),
      style: AppTextStyles.avatarInitials.copyWith(
        color: isActive ? AppColors.primary : AppColors.textFaint,
      ),
    ),
  );
}

class _AssignmentChoice {
  const _AssignmentChoice({this.targetCompletion});

  final DateTime? targetCompletion;
}

/// Confirms the pairing and offers a target completion date.
///
/// The date is optional and is not in the Figma flow. It writes to
/// `WorkOrder.scheduledFor`, which already existed and which the OVERDUE
/// metric is measured against — without it that card could only ever read
/// zero.
class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.report, required this.person});

  final DamageReport report;
  final AppUser person;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  DateTime? _target;

  @override
  Widget build(BuildContext context) {
    final trade = widget.person.specialization?.assignedPersonnelLabel;
    final category = widget.report.category;
    final mismatched =
        category != null &&
        trade != null &&
        trade != category.assignedPersonnelLabel;

    return AlertDialog(
      title: const Text('Assign this report'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.report.title, style: AppTextStyles.workOrderTitle),
          const SizedBox(height: 4),
          Text(
            'To ${widget.person.fullName}'
            '${trade == null ? '' : ' · $trade'}',
            style: AppTextStyles.bodySmall,
          ),
          if (mismatched) ...[
            const SizedBox(height: 12),
            // A warning, not a block: the manuscript routes categories to
            // trades, but the administrator decides — the matching person
            // may be on leave.
            Text(
              'This is a ${category.label} report, usually handled by a '
              '${category.assignedPersonnelLabel}.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.priorityHighForeground,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _target == null
                      ? 'No target completion date'
                      : 'Target: ${DateFormat('MMM d, y').format(_target!)}',
                  style: AppTextStyles.fieldValue,
                ),
              ),
              TextButton(
                onPressed: _pickDate,
                child: Text(_target == null ? 'Set date' : 'Change'),
              ),
              if (_target != null)
                TextButton(
                  onPressed: () => setState(() => _target = null),
                  child: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(_AssignmentChoice(targetCompletion: _target)),
          child: const Text('Assign'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _target ?? now.add(const Duration(days: 3)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _target = picked);
  }
}
