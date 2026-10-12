import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/enums/task_status.dart';
import '../../../core/enums/work_order_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../accomplishment/data/models/accomplishment_report.dart';
import '../../accomplishment/data/models/recorded_material.dart';
import '../../accomplishment/presentation/material_sheets.dart';
import '../../tasks/data/models/maintenance_task.dart';
import '../../tasks/data/repositories/task_repository_impl.dart';
import '../../tasks/domain/task_day.dart';
import '../../tools/data/models/tool_loan.dart';
import '../../user_management/presentation/personnel_providers.dart';
import '../data/models/work_order.dart';
import 'personnel/personnel_providers.dart';
import 'work_order_detail_controller.dart';

/// A work order in the console (Objective 5): its tasks — which the
/// administrator adds and the technician ticks (Chris, 2026-10-12) — the
/// note to the technician, what was used, and the accomplishment report
/// to sign off or send back.
///
/// No Figma frame exists for it; it follows the report page's layout and
/// components. Opened from a work order's number on the board or in the
/// table.
class WorkOrderDetailScreen extends ConsumerWidget {
  const WorkOrderDetailScreen({required this.workOrderId, super.key});

  final String workOrderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: const EdgeInsets.all(32),
    child: AsyncValueView<WorkOrder>(
      value: ref.watch(workOrderDetailProvider(workOrderId)),
      onRetry: () => ref.invalidate(workOrderDetailProvider(workOrderId)),
      data: (workOrder) => _Detail(workOrder: workOrder),
    ),
  );
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = MyWork.isOpen(workOrder.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => context.go(RoutePaths.adminWorkOrders),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Work order management'),
        ),
        const SizedBox(height: 8),
        Text(
          DisplayId.workOrder(workOrder.id),
          style: AppTextStyles.monoIdentifier,
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(workOrder.title, style: AppTextStyles.pageTitle),
            ),
            StatusChip.workOrder(workOrder.status),
            const SizedBox(width: 8),
            PriorityChip(level: workOrder.priority),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final main = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AccomplishmentCard(workOrder: workOrder),
                const SizedBox(height: 16),
                _TasksCard(workOrder: workOrder, open: open),
              ],
            );
            final side = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DetailsCard(workOrder: workOrder),
                const SizedBox(height: 16),
                _NoteCard(workOrder: workOrder),
                const SizedBox(height: 16),
                _UsedCard(workOrder: workOrder, open: open),
              ],
            );
            if (constraints.maxWidth >= 1000) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: main),
                  const SizedBox(width: 16),
                  Expanded(child: side),
                ],
              );
            }
            return Column(children: [main, const SizedBox(height: 16), side]);
          },
        ),
      ],
    );
  }
}

/// Shows [result]'s failure, or [success].
void _report(BuildContext context, Result<void> result, String success) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(switch (result) {
      Success() => SnackBar(content: Text(success)),
      Error(:final failure) => SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ),
    });
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTextStyles.fieldLabel),
        const SizedBox(height: 4),
        value,
      ],
    ),
  );
}

class _DetailsCard extends ConsumerWidget {
  const _DetailsCard({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(personnelNamesProvider);
    final when = DateFormat('MMM d, y · h:mm a');
    String at(DateTime? moment) =>
        moment == null ? '—' : when.format(moment.toLocal());

    return SectionCard(
      title: 'Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
            workOrder.reportIds.length == 1 ? 'Report' : 'Reports',
            Wrap(
              spacing: 8,
              children: [
                for (final id in workOrder.reportIds)
                  TextButton(
                    onPressed: () =>
                        context.go(RoutePaths.adminReportDetailFor(id)),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(DisplayId.report(id)),
                  ),
              ],
            ),
          ),
          _Field(
            'Facility',
            Text(
              workOrder.facilityName ?? '—',
              style: AppTextStyles.fieldValue,
            ),
          ),
          _Field(
            'Assigned to',
            Text(
              workOrder.assignedPersonnelIds
                  .map((id) => names[id] ?? id)
                  .join(', ')
                  .ifEmpty('Nobody'),
              style: AppTextStyles.fieldValue,
            ),
          ),
          _Field(
            'Damage type',
            Text(workOrder.category.label, style: AppTextStyles.fieldValue),
          ),
          _Field(
            'Target date',
            Text(
              workOrder.scheduledFor == null
                  ? 'None set'
                  : DateFormat('MMM d, y')
                        .format(workOrder.scheduledFor!.toLocal()),
              style: AppTextStyles.fieldValue,
            ),
          ),
          _Field(
            'Assigned',
            Text(at(workOrder.createdAt), style: AppTextStyles.fieldValue),
          ),
          _Field(
            'Started',
            Text(at(workOrder.startedAt), style: AppTextStyles.fieldValue),
          ),
          _Field(
            'Signed off',
            Text(at(workOrder.completedAt), style: AppTextStyles.fieldValue),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// The note shown at the top of the work order on the technician's phone.
class _NoteCard extends ConsumerStatefulWidget {
  const _NoteCard({required this.workOrder});

  final WorkOrder workOrder;

  @override
  ConsumerState<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends ConsumerState<_NoteCard> {
  late final _note = TextEditingController(
    text: widget.workOrder.adminNotes ?? '',
  );
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _NoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final saved = widget.workOrder.adminNotes ?? '';
    // Follow a note saved elsewhere — a send-back writes one — unless
    // there are edits here.
    if ((oldWidget.workOrder.adminNotes ?? '') == _note.text) {
      _note.text = saved;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final text = _note.text.trim();
    final result = await ref
        .read(workOrderDetailControllerProvider)
        .saveNote(widget.workOrder.id, text.isEmpty ? null : text);
    if (!mounted) return;
    setState(() => _busy = false);
    _report(context, result, 'Note saved. The technician sees it now.');
  }

  @override
  Widget build(BuildContext context) {
    final changed = _note.text.trim() != (widget.workOrder.adminNotes ?? '');
    return SectionCard(
      title: 'Note to the technician',
      subtitle: 'Shown at the top of the work order on their phone.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _note,
            enabled: !_busy,
            minLines: 2,
            maxLines: 5,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'e.g. Please finish before the 2 PM lab session.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: changed && !_busy ? _save : null,
              child: Text(_busy ? 'Saving…' : 'Save note'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tasks, and adding one.
class _TasksCard extends ConsumerWidget {
  const _TasksCard({required this.workOrder, required this.open});

  final WorkOrder workOrder;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
    title: 'Tasks',
    subtitle: open
        ? 'The technician ticks these off on their phone, with photo proof.'
        : 'This work order is ${workOrder.status.title}; its tasks no '
              'longer change.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AsyncValueView<List<MaintenanceTask>>(
          value: ref.watch(workOrderTasksProvider(workOrder.id)),
          loadingHeight: 60,
          onRetry: () => ref.invalidate(workOrderTasksProvider(workOrder.id)),
          isEmpty: (tasks) => tasks.isEmpty,
          emptyIcon: Icons.checklist_rounded,
          emptyMessage: 'No tasks yet.',
          data: (tasks) => Column(
            children: [
              for (final task in tasks) _TaskRow(task: task, canDelete: open),
            ],
          ),
        ),
        if (open) ...[
          const Divider(height: 32),
          _AddTaskForm(workOrderId: workOrder.id),
        ],
      ],
    ),
  );
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task, required this.canDelete});

  final MaintenanceTask task;
  final bool canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdue = TaskDay.isOverdue(task, DateTime.now());
    final due = task.dueDate;
    final details = [
      if (due != null)
        '${overdue ? 'Overdue, due' : 'Due'} '
            '${DateFormat('MMM d').format(due.toLocal())}',
      task.status.label,
      if (task.proofPhotoUrls.isNotEmpty)
        task.proofPhotoUrls.length == 1
            ? '1 proof photo'
            : '${task.proofPhotoUrls.length} proof photos',
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        switch (task.status) {
          TaskStatus.pending => Icons.radio_button_unchecked,
          TaskStatus.inProgress => Icons.timelapse_rounded,
          TaskStatus.completed => Icons.check_circle_rounded,
        },
        color: task.status == TaskStatus.completed
            ? AppColors.progressCompleted
            : AppColors.accentGold,
      ),
      title: Text(
        task.title,
        style: AppTextStyles.fieldValue.copyWith(
          decoration: task.status == TaskStatus.completed
              ? TextDecoration.lineThrough
              : null,
        ),
      ),
      subtitle: Text(
        [?task.description, details.join(' · ')].join('\n'),
        style: AppTextStyles.bodySmall.copyWith(
          color: overdue ? AppColors.error : null,
        ),
      ),
      isThreeLine: task.description != null,
      trailing: canDelete && task.status != TaskStatus.completed
          ? IconButton(
              tooltip: 'Remove "${task.title}"',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final result = await ref
                    .read(workOrderDetailControllerProvider)
                    .deleteTask(task.id);
                if (context.mounted) {
                  _report(context, result, 'Task removed.');
                }
              },
            )
          : null,
    );
  }
}

class _AddTaskForm extends ConsumerStatefulWidget {
  const _AddTaskForm({required this.workOrderId});

  final String workOrderId;

  @override
  ConsumerState<_AddTaskForm> createState() => _AddTaskFormState();
}

class _AddTaskFormState extends ConsumerState<_AddTaskForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  DateTime _due = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _add() async {
    setState(() => _busy = true);
    final result = await ref
        .read(workOrderDetailControllerProvider)
        .addTask(
          workOrderId: widget.workOrderId,
          title: _title.text,
          description: _description.text,
          // Noon on the day, so the day survives any time-zone shift.
          dueDate: DateTime(_due.year, _due.month, _due.day, 12),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isSuccess) {
      _title.clear();
      _description.clear();
    }
    _report(context, result, 'Task added. The technician has been told.');
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('ADD A TASK', style: AppTextStyles.fieldLabel),
      const SizedBox(height: 8),
      TextField(
        controller: _title,
        enabled: !_busy,
        maxLength: TaskRepositoryImpl.titleLimit,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Task',
          hintText: 'e.g. Replace the switch cover',
          border: OutlineInputBorder(),
          counterText: '',
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _description,
        enabled: !_busy,
        maxLength: TaskRepositoryImpl.descriptionLimit,
        decoration: const InputDecoration(
          labelText: 'Details (optional)',
          border: OutlineInputBorder(),
          counterText: '',
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text('Due ${DateFormat('MMM d, y').format(_due)}'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _busy || _title.text.trim().isEmpty ? null : _add,
            child: Text(_busy ? 'Adding…' : 'Add task'),
          ),
        ],
      ),
    ],
  );
}

/// Materials recorded while the work is open, and the tools borrowed for
/// it.
class _UsedCard extends ConsumerWidget {
  const _UsedCard({required this.workOrder, required this.open});

  final WorkOrder workOrder;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(personnelNamesProvider);
    final when = DateFormat('MMM d, h:mm a');
    final recorded = switch (ref.watch(
      recordedMaterialsProvider(workOrder.id),
    )) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <RecordedMaterial>[],
    };
    final loans = switch (ref.watch(workOrderLoansProvider(workOrder.id))) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <ToolLoan>[],
    };

    return SectionCard(
      title: 'Materials and tools',
      subtitle:
          'Recorded by the technician; materials come off stock when '
          'the accomplishment report is filed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (open) ...[
            const Text('RECORDED SO FAR', style: AppTextStyles.fieldLabel),
            const SizedBox(height: 6),
            if (recorded.isEmpty)
              const Text('None.', style: AppTextStyles.bodySmall)
            else
              for (final material in recorded)
                Text(
                  '${formatQuantity(material.usage.quantityUsed)} '
                  '${material.usage.unitOfMeasurement} '
                  '${material.usage.itemName}',
                  style: AppTextStyles.fieldValue,
                ),
            const SizedBox(height: 16),
          ],
          const Text('TOOLS', style: AppTextStyles.fieldLabel),
          const SizedBox(height: 6),
          if (loans.isEmpty)
            const Text('None borrowed for it.', style: AppTextStyles.bodySmall)
          else
            for (final loan in loans)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${loan.toolName} — ${names[loan.borrowedBy] ?? 'a technician'}, '
                  '${when.format(loan.borrowedAt.toLocal())}'
                  '${loan.returnedAt == null ? ' · still out' : ' · returned ${when.format(loan.returnedAt!.toLocal())}, ${loan.conditionOnReturn?.label.toLowerCase()}'}',
                  style: AppTextStyles.fieldValue,
                ),
              ),
        ],
      ),
    );
  }
}

/// The accomplishment reports filed, newest first, and the review of the
/// latest (Objective 5.B).
class _AccomplishmentCard extends ConsumerWidget {
  const _AccomplishmentCard({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
    title: 'Accomplishment report',
    child: AsyncValueView<List<AccomplishmentReport>>(
      value: ref.watch(workOrderAccomplishmentsProvider(workOrder.id)),
      loadingHeight: 80,
      onRetry: () =>
          ref.invalidate(workOrderAccomplishmentsProvider(workOrder.id)),
      isEmpty: (reports) => reports.isEmpty,
      emptyIcon: Icons.assignment_turned_in_outlined,
      emptyMessage:
          'Not submitted yet. The technician files it from their phone when '
          'the work is done.',
      data: (reports) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final report in reports) ...[
            _ReportBody(
              report: report,
              workOrder: workOrder,
              isLatest: report == reports.first,
            ),
            if (report != reports.last) const Divider(height: 32),
          ],
        ],
      ),
    ),
  );
}

class _ReportBody extends ConsumerStatefulWidget {
  const _ReportBody({
    required this.report,
    required this.workOrder,
    required this.isLatest,
  });

  final AccomplishmentReport report;
  final WorkOrder workOrder;
  final bool isLatest;

  @override
  ConsumerState<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends ConsumerState<_ReportBody> {
  bool _busy = false;

  Future<void> _approve() async {
    setState(() => _busy = true);
    final result = await ref
        .read(workOrderDetailControllerProvider)
        .review(reportId: widget.report.id, approve: true);
    if (!mounted) return;
    setState(() => _busy = false);
    _report(context, result, 'Signed off. The work order is completed.');
  }

  Future<void> _sendBack() async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => const _SendBackDialog(),
    );
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    final result = await ref
        .read(workOrderDetailControllerProvider)
        .review(reportId: widget.report.id, approve: false, note: note);
    if (!mounted) return;
    setState(() => _busy = false);
    _report(context, result, 'Sent back. The technician has been told.');
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final names = ref.watch(personnelNamesProvider);
    final when = DateFormat('MMM d, y · h:mm a');
    final reviewedAt = report.reviewedAt;
    final awaiting =
        widget.isLatest &&
        reviewedAt == null &&
        widget.workOrder.status == WorkOrderStatus.forReview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Submitted by ${names[report.submittedBy] ?? 'the technician'}, '
          '${when.format(report.submittedAt.toLocal())}',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 10),
        Text(report.completionNotes, style: AppTextStyles.fieldValue),
        if (report.photoUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final url in report.photoUrls)
                InkWell(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => Dialog(
                      child: InteractiveViewer(child: Image.network(url)),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      url,
                      width: 120,
                      height: 90,
                      fit: BoxFit.cover,
                      semanticLabel: 'Photo of the finished work',
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(
                            width: 120,
                            height: 90,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        const Text('MATERIALS USED', style: AppTextStyles.fieldLabel),
        const SizedBox(height: 4),
        if (report.materialsUsed.isEmpty)
          const Text('None.', style: AppTextStyles.bodySmall)
        else ...[
          for (final material in report.materialsUsed)
            Text(
              '${formatQuantity(material.quantityUsed)} '
              '${material.unitOfMeasurement} ${material.itemName}',
              style: AppTextStyles.fieldValue,
            ),
          if (report.inventoryDeducted)
            const Text(
              'Taken off stock when the report was filed.',
              style: AppTextStyles.bodySmall,
            ),
        ],
        const SizedBox(height: 16),
        if (awaiting)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _approve,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Approve and sign off'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _sendBack,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Send back for rework'),
              ),
            ],
          )
        else if (reviewedAt != null)
          Text(
            '${widget.isLatest && widget.workOrder.status == WorkOrderStatus.completed ? 'Signed off' : 'Reviewed'} '
            '${when.format(reviewedAt.toLocal())}.',
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// Why the work goes back: shown to the technician at the top of the work
/// order.
class _SendBackDialog extends StatefulWidget {
  const _SendBackDialog();

  @override
  State<_SendBackDialog> createState() => _SendBackDialogState();
}

class _SendBackDialogState extends State<_SendBackDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Send back for rework?'),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _note,
        autofocus: true,
        maxLines: 3,
        maxLength: 500,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'What still needs doing',
          hintText: 'Shown to the technician at the top of the work order',
          border: OutlineInputBorder(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _note.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_note.text.trim()),
        child: const Text('Send back'),
      ),
    ],
  );
}
