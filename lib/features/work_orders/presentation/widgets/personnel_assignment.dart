import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/widgets/person_avatar.dart';
import '../../../damage_reports/data/models/damage_report.dart';
import '../../../user_management/data/models/app_user.dart';
import '../../../user_management/presentation/personnel_directory_providers.dart';
import '../../../user_management/presentation/personnel_providers.dart';
import '../../data/models/work_order.dart';
import '../assignment_controller.dart';
import '../work_order_providers.dart';

// Assigning a report to a technician: the pieces the report's own page
// (2026-11-26) and the Task Assignment screen share, so the two cannot
// assign differently.

/// The personnel whose trade handles [category] (manuscript Table 3.3):
/// Electrical to Electricians, Plumbing to Plumbing Personnel, Structural
/// and Carpentry to Structural Maintenance Personnel, Air Conditioning to
/// Aircon Technicians, Cleaning and Sanitation to Janitorial Personnel.
/// Active accounts first, then the least busy.
///
/// A filter, since the adviser's consultation (2026-11-26): a lights
/// report lists electricians only. With no category, nobody matches.
List<AppUser> personnelOfTrade(List<AppUser> people, DamageCategory? category) {
  if (category == null) return const [];
  return rankedForCategory([
    for (final person in people)
      if (person.specialization?.assignedPersonnelLabel ==
          category.assignedPersonnelLabel)
        person,
  ], category);
}

/// The work orders each person holds now, by their id: not completed and
/// not archived, newest first. A person's current workload.
final personnelWorkloadProvider = Provider<Map<String, List<WorkOrder>>>((ref) {
  final workOrders =
      ref
          .watch(workOrdersStreamProvider)
          .value
          ?.fold((list) => list, (_) => const <WorkOrder>[]) ??
      const <WorkOrder>[];
  final held = <String, List<WorkOrder>>{};
  for (final workOrder in workOrders) {
    if (workOrder.isArchived || workOrder.status == WorkOrderStatus.completed) {
      continue;
    }
    for (final id in workOrder.assignedPersonnelIds) {
      (held[id] ??= []).add(workOrder);
    }
  }
  for (final list in held.values) {
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  return held;
});

/// Whether a person can take work now, in the words the panels show.
enum AssignmentAvailability {
  available('Available'),
  busy('Busy'),
  onLeave('On leave'),
  inactive('Inactive');

  const AssignmentAvailability(this.label);

  final String label;

  /// [held] is how many work orders the person holds now.
  static AssignmentAvailability of(AppUser person, {required int held}) {
    if (person.accountStatus != AccountStatus.active) return inactive;
    if (StaffStatus.of(person) == StaffStatus.onLeave) return onLeave;
    return held > 0 ? busy : available;
  }

  /// Whether work can be given to them. Busy people can take more; the
  /// administrator sees how much they hold.
  bool get canTakeWork => this == available || this == busy;

  Color get color => switch (this) {
    available => AppColors.presenceActiveText,
    busy => AppColors.accountPending,
    onLeave || inactive => AppColors.textFaint,
  };
}

/// "2 current tasks: Flickering lights; Leaking pipe" — what a person is
/// working on now, the first few by name.
String workloadSummary(List<WorkOrder> held, {int named = 2}) {
  if (held.isEmpty) return 'No current tasks';
  final count = '${held.length} current task${held.length == 1 ? '' : 's'}';
  final names = held.take(named).map((w) => w.title).join('; ');
  final more = held.length > named ? ' and ${held.length - named} more' : '';
  return '$count: $names$more';
}

/// One person who can take [report]: who they are and their trade, their
/// availability, what they hold now, and Assign.
class PersonnelAssignRow extends ConsumerStatefulWidget {
  const PersonnelAssignRow({
    required this.person,
    required this.report,
    super.key,
  });

  final AppUser person;
  final DamageReport report;

  @override
  ConsumerState<PersonnelAssignRow> createState() => _PersonnelAssignRowState();
}

class _PersonnelAssignRowState extends ConsumerState<PersonnelAssignRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final held = ref.watch(personnelWorkloadProvider)[person.id] ?? const [];
    final availability = AssignmentAvailability.of(person, held: held.length);
    final canAssign = availability.canTakeWork && !_busy;

    final who = Row(
      children: [
        PersonAvatar(
          fullName: person.fullName,
          isActive: availability.canTakeWork,
        ),
        const SizedBox(width: 12),
        Expanded(
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
      ],
    );
    final state = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: availability.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              availability.label,
              style: AppTextStyles.presenceLabel.copyWith(
                color: availability.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(workloadSummary(held), style: AppTextStyles.bodySmall),
      ],
    );
    final action = Tooltip(
      message: switch (availability) {
        AssignmentAvailability.inactive =>
          'This account is inactive and cannot take work.',
        AssignmentAvailability.onLeave => '${person.fullName} is on leave.',
        _ => 'Assign ${widget.report.title} to ${person.fullName}',
      },
      child: FilledButton(
        key: ValueKey('assign-${person.id}'),
        onPressed: canAssign ? _assign : null,
        child: _busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Assign'),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                who,
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.only(left: 52), child: state),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 4, child: who),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: state),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }

  Future<void> _assign() async {
    await assignReportTo(
      context,
      ref,
      widget.report,
      widget.person,
      onConfirmed: () {
        if (mounted) setState(() => _busy = true);
      },
    );
    if (mounted) setState(() => _busy = false);
  }
}

/// Confirms giving [report] to [person], with a target date, then raises
/// the work order: the report moves to Assigned and the technician and the
/// requestor are notified, in one database call. Says how it went. True
/// when it was assigned. [onConfirmed] runs once the dialog is confirmed,
/// as the call is made: where the caller shows that it is on its way.
Future<bool> assignReportTo(
  BuildContext context,
  WidgetRef ref,
  DamageReport report,
  AppUser person, {
  VoidCallback? onConfirmed,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showDialog<AssignmentChoice>(
    context: context,
    builder: (_) => AssignDialog(report: report, person: person),
  );
  if (choice == null) return false;
  onConfirmed?.call();

  final result = await ref
      .read(assignmentControllerProvider)
      .assign(
        reportId: report.id,
        personnelId: person.id,
        targetCompletion: choice.targetCompletion,
      );
  return result.fold(
    (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${report.title} assigned to ${person.fullName}. They and the '
            'requestor have been notified.',
          ),
        ),
      );
      return true;
    },
    (failure) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
      return false;
    },
  );
}

/// What the Assign dialog was confirmed with.
class AssignmentChoice {
  const AssignmentChoice({this.targetCompletion});

  final DateTime? targetCompletion;
}

/// Confirms the pairing and offers a target completion date.
///
/// The date is optional and is not in the Figma flow. It writes to
/// `WorkOrder.scheduledFor`, which already existed and which the OVERDUE
/// metric is measured against — without it that card could only ever read
/// zero. A rescheduled report offers the date it was moved to.
class AssignDialog extends StatefulWidget {
  const AssignDialog({required this.report, required this.person, super.key});

  final DamageReport report;
  final AppUser person;

  @override
  State<AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<AssignDialog> {
  late DateTime? _target = _startingTarget();

  DateTime? _startingTarget() {
    final moved = widget.report.rescheduledTo?.toLocal();
    if (moved == null) return null;
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(moved);
    return day.isBefore(today) ? null : day;
  }

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
          const SizedBox(height: 12),
          const Text(
            'A work order is created and the report moves to Assigned. The '
            'technician and the requestor are notified.',
            style: AppTextStyles.bodySmall,
          ),
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
                  .pop(AssignmentChoice(targetCompletion: _target)),
          child: const Text('Assign'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    // From the start of today, so a date picked today can be opened again.
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _target ?? today.add(const Duration(days: 3)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _target = picked);
  }
}
