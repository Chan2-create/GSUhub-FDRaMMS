import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../settings/presentation/holiday_providers.dart';
import '../../../user_management/data/models/app_user.dart';
import '../../../user_management/presentation/personnel_providers.dart';
import '../../../work_orders/presentation/widgets/personnel_assignment.dart';
import '../../data/models/damage_report.dart';
import '../report_review_controller.dart';

/// Assign personnel, on the report's own page, once it is approved
/// (2026-11-26, the adviser's consultation): the report is handled from
/// start to finish where it was reviewed, without going to Task
/// Assignment.
///
/// Lists the personnel of the report's trade only (Table 3.3), each with
/// their availability and the work they hold now. Assigning raises the
/// work order, moves the report to Assigned and notifies the technician
/// and the requestor. When nobody, or no equipment, is free, Schedule sets
/// the date the work waits for, with a reason; both reach the requestor.
///
/// **Schedule, not Reschedule (2026-11-26):** when a report is first
/// handled the administrator is scheduling it. Once a work order exists,
/// rescheduling and reassigning are done from the work order's page.
class ReportAssignmentSection extends ConsumerWidget {
  const ReportAssignmentSection({required this.report, super.key});

  final DamageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = report.category;
    return SectionCard(
      key: const ValueKey('report-assignment'),
      title: 'Assign personnel',
      subtitle: category == null
          ? 'Confirm the damage type first: it decides who can take the work.'
          : '${category.label} reports go to '
                '${category.assignedPersonnelLabel} (Table 3.3). Choose who '
                'takes it, or schedule it when nobody can yet.',
      trailing: OutlinedButton.icon(
        key: const ValueKey('schedule-report'),
        onPressed: () => showScheduleDialog(context, ref, report),
        icon: const Icon(Icons.event_outlined, size: 18),
        label: Text(report.isRescheduled ? 'Change schedule' : 'Schedule'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (report.isRescheduled) ...[
            ScheduledNotice(report: report),
            const SizedBox(height: 16),
          ],
          if (!report.isAssignable)
            const Text(
              'Confirm the damage type and the official priority in the '
              'review above before assigning the work.',
              style: AppTextStyles.bodySmall,
            )
          else
            AsyncValueView<List<AppUser>>(
              value: ref.watch(personnelStreamProvider),
              loadingHeight: 120,
              onRetry: () => ref.invalidate(personnelStreamProvider),
              data: (people) {
                final matching = personnelOfTrade(people, category);
                if (matching.isEmpty) {
                  return Text(
                    'No ${category!.assignedPersonnelLabel} account is '
                    'registered. Schedule the report until one can take '
                    'it, or add one in User Accounts.',
                    style: AppTextStyles.bodySmall,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, person) in matching.indexed) ...[
                      if (index > 0)
                        const Divider(height: 1, color: AppColors.borderSubtle),
                      PersonnelAssignRow(person: person, report: report),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// "Scheduled for Dec 1, 2026" and why, while the report waits for that
/// date.
class ScheduledNotice extends StatelessWidget {
  const ScheduledNotice({required this.report, super.key});

  final DamageReport report;

  static final DateFormat _date = DateFormat('MMM d, y');

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.statusReviewBackground,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.event_repeat_outlined,
            size: 18,
            color: AppColors.statusReviewForeground,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Scheduled for '
            '${_date.format(report.rescheduledTo!.toLocal())}: '
            '${report.rescheduleReason ?? 'no reason recorded'}',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.statusReviewForeground,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Asks for the reason and the date the work is moved to, both required,
/// and schedules the report.
Future<void> showScheduleDialog(
  BuildContext context,
  WidgetRef ref,
  DamageReport report,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final moved = await showDialog<DateTime>(
    context: context,
    builder: (_) => _ScheduleDialog(report: report),
  );
  if (moved == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Scheduled for ${DateFormat('MMM d, y').format(moved)}. The '
        'requestor has been told why.',
      ),
    ),
  );
}

class _ScheduleDialog extends ConsumerStatefulWidget {
  const _ScheduleDialog({required this.report});

  final DamageReport report;

  @override
  ConsumerState<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends ConsumerState<_ScheduleDialog> {
  static const int reasonLimit = 500;

  late final _reason = TextEditingController(
    text: widget.report.rescheduleReason,
  );
  DateTime? _date;
  String? _reasonError;
  String? _dateError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// A working day only: no Saturday, Sunday or holiday (2026-11-26).
  Future<void> _pickDate() async {
    final picked = await pickSchedulingDay(
      context,
      ref,
      initial: _date ?? DateTime.now().add(const Duration(days: 1)),
      helpText: 'Schedule for',
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _dateError = null;
      });
    }
  }

  Future<void> _save() async {
    final reason = _reason.text.trim();
    setState(() {
      _reasonError = reason.isEmpty
          ? 'Give the reason the work has to wait.'
          : null;
      _dateError = _date == null
          ? 'Choose the date it is scheduled for.'
          : null;
      _error = null;
    });
    if (_reasonError != null || _dateError != null) return;

    setState(() => _busy = true);
    final result = await ref
        .read(reportReviewControllerProvider)
        .reschedule(widget.report.id, reason: reason, rescheduledTo: _date!);
    if (!mounted) return;
    result.fold(
      (_) => Navigator.of(context).pop(_date),
      (failure) => setState(() {
        _busy = false;
        _error = failure.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Schedule this report'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'For when no personnel or equipment is available yet. The '
              'report stays approved, waiting for the date; the requestor '
              'sees the date and the reason. Weekdays only: Saturdays, '
              'Sundays and the holidays in Settings cannot be picked.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('schedule-reason'),
              controller: _reason,
              enabled: !_busy,
              autofocus: true,
              maxLines: 3,
              maxLength: reasonLimit,
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. The only electrician is on leave until Monday.',
                errorText: _reasonError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_reasonError != null) setState(() => _reasonError = null);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _date == null
                        ? 'No date chosen'
                        : 'Scheduled for ${DateFormat('EEE, MMM d, y').format(_date!)}',
                    style: AppTextStyles.fieldValue,
                  ),
                ),
                TextButton(
                  key: const ValueKey('schedule-date'),
                  onPressed: _busy ? null : _pickDate,
                  child: Text(_date == null ? 'Choose date' : 'Change'),
                ),
              ],
            ),
            if (_dateError case final message?)
              Text(
                message,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
              ),
            if (_error case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('schedule-save'),
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving…' : 'Schedule'),
      ),
    ],
  );
}
