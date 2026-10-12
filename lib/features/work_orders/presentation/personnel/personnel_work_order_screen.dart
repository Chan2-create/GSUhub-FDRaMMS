import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/di/repository_providers.dart';
import '../../../../core/enums/task_status.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/services/photo_picker_service.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../shells/personnel/personnel_shell.dart';
import '../../../accomplishment/data/models/accomplishment_report.dart';
import '../../../accomplishment/data/models/material_usage.dart';
import '../../../accomplishment/data/models/recorded_material.dart';
import '../../../accomplishment/data/repositories/accomplishment_report_repository_impl.dart';
import '../../../accomplishment/presentation/material_sheets.dart';
import '../../../reporting/data/models/damage_report.dart';
import '../../../reporting/presentation/report_providers.dart';
import '../../../tasks/presentation/widgets/task_tiles.dart';
import '../../../tools/presentation/tool_sheets.dart';
import '../../data/models/work_order.dart';
import 'personnel_providers.dart';
import 'personnel_work_controller.dart';
import 'widgets/personnel_widgets.dart';

/// One work order in the personnel app (Objectives 5.A–5.C; manuscript
/// Figure 25, Chris's export Group 42): its status, GSU's note, the place
/// and the damage, its tasks, the materials and tools used on it, and the
/// accomplishment report — written here, and shown once filed.
///
/// Departures from the frame, flagged: "Materials Assigned" is the
/// materials recorded as used (pre-assignment and "Request Additional
/// Materials" belong to Objective 6), and the tasks and tools cards are
/// additions the frame has no room for.
class PersonnelWorkOrderScreen extends ConsumerWidget {
  const PersonnelWorkOrderScreen({required this.workOrderId, super.key});

  final String workOrderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncValueView<WorkOrder>(
        value: ref.watch(personnelWorkOrderProvider(workOrderId)),
        onRetry: () => ref.invalidate(personnelWorkOrderProvider(workOrderId)),
        data: (workOrder) => _Detail(workOrder: workOrder),
      );
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = MyWork.isOpen(workOrder.status);
    final reports = switch (ref.watch(
      myAccomplishmentReportsProvider(workOrder.id),
    )) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <AccomplishmentReport>[],
    };
    final latest = reports.isEmpty ? null : reports.first;
    final note = workOrder.adminNotes;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, personnelBottomInset(context)),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go(RoutePaths.personnelDashboard),
              icon: const Icon(
                Icons.arrow_back,
                color: AppColors.myReportsTitle,
              ),
            ),
            Expanded(
              child: Text(
                DisplayId.workOrder(workOrder.id),
                style: AppTextStyles.personnelWorkOrderId.copyWith(
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        _StatusCard(workOrder: workOrder),
        if (note != null) ...[
          const SizedBox(height: 16),
          _NoteBanner(note: note),
        ],
        const SizedBox(height: 16),
        _PlaceCard(workOrder: workOrder),
        const SizedBox(height: 16),
        _TasksCard(workOrder: workOrder, open: open),
        const SizedBox(height: 16),
        _MaterialsCard(workOrder: workOrder, open: open, latest: latest),
        const SizedBox(height: 16),
        _ToolsCard(workOrder: workOrder, open: open),
        if (workOrder.status == WorkOrderStatus.inProgress) ...[
          const SizedBox(height: 16),
          _CompletionForm(workOrder: workOrder),
        ],
        if (latest != null) ...[
          const SizedBox(height: 16),
          _SubmittedReport(report: latest, workOrder: workOrder),
        ],
      ],
    );
  }
}

/// The status pill, when it happened, and Start work (Group 42).
class _StatusCard extends ConsumerStatefulWidget {
  const _StatusCard({required this.workOrder});

  final WorkOrder workOrder;

  @override
  ConsumerState<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends ConsumerState<_StatusCard> {
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    final result = await ref
        .read(personnelWorkControllerProvider)
        .startWork(widget.workOrder.id);
    if (!mounted) return;
    setState(() => _busy = false);
    reportOutcome(
      context,
      result,
      success: 'Work started. The requestor has been told.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final workOrder = widget.workOrder;
    final when = DateFormat('MMM d, h:mm a');
    final (icon, color) = switch (workOrder.status) {
      WorkOrderStatus.pending => (
        Icons.schedule_rounded,
        AppColors.personnelWorkOrderCard,
      ),
      WorkOrderStatus.inProgress => (
        Icons.timelapse_rounded,
        AppColors.personnelStatusPill,
      ),
      WorkOrderStatus.forReview => (
        Icons.hourglass_top_rounded,
        AppColors.progressInProgress,
      ),
      WorkOrderStatus.completed => (
        Icons.check_circle_rounded,
        AppColors.progressCompleted,
      ),
    };
    final detail = switch (workOrder.status) {
      WorkOrderStatus.pending =>
        'Assigned ${when.format(workOrder.createdAt.toLocal())}'
            '${workOrder.scheduledFor == null ? '' : ' · Due ${DateFormat('MMM d').format(workOrder.scheduledFor!.toLocal())}'}',
      WorkOrderStatus.inProgress =>
        'Started ${when.format((workOrder.startedAt ?? workOrder.updatedAt).toLocal())}',
      WorkOrderStatus.forReview => 'Submitted — waiting for GSU to sign it off',
      WorkOrderStatus.completed =>
        'Signed off ${when.format((workOrder.completedAt ?? workOrder.updatedAt).toLocal())}',
    };

    return PersonnelCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    workStatusLabel(workOrder.status).toUpperCase(),
                    style: AppTextStyles.personnelCardTitle.copyWith(
                      color: Colors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: AppTextStyles.personnelCardBody,
          ),
          const SizedBox(height: 4),
          Text(workOrder.title, style: AppTextStyles.personnelCardTitle),
          if (workOrder.status == WorkOrderStatus.pending) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(_busy ? 'Starting…' : 'Start work'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The administrator's note, pale gold with a gold edge (Group 42).
class _NoteBanner extends StatelessWidget {
  const _NoteBanner({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) => PersonnelCard(
    color: AppColors.trackingNoteFill,
    edge: AppColors.accentGold,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.trackingAccentText,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'GSU: "$note"',
            style: AppTextStyles.personnelCardTitle.copyWith(
              fontSize: 15,
              color: AppColors.warmText,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Where the work is, the damage type and priority, and what is wrong
/// (Group 42), from the report it came from.
class _PlaceCard extends ConsumerWidget {
  const _PlaceCard({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportId = workOrder.reportIds.isEmpty
        ? null
        : workOrder.reportIds.first;
    final report = reportId == null
        ? null
        : switch (ref.watch(reportByIdProvider(reportId))) {
            AsyncData(value: Success(:final value)) => value,
            _ => null,
          };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          top: BorderSide(color: AppColors.accentGold, width: 4),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.warmFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.accentGold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workOrder.facilityName ?? 'Facility not recorded',
                      style: AppTextStyles.personnelGreeting.copyWith(
                        fontSize: 18,
                      ),
                    ),
                    // The room, when it says more than the building.
                    if (report?.locationDescription case final where?
                        when where != workOrder.facilityName)
                      Text(where, style: AppTextStyles.personnelSubtitle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PersonnelChip(
                workOrder.category.label,
                background: AppColors.sidebarBackground,
                foreground: Colors.white,
              ),
              PriorityTag(workOrder.priority),
            ],
          ),
          const Divider(height: 28),
          const Text('DAMAGE DESCRIPTION', style: AppTextStyles.personnelChip),
          const SizedBox(height: 6),
          Text(
            workOrder.description,
            style: AppTextStyles.personnelSubtitle.copyWith(
              color: AppColors.personnelTitle,
              fontSize: 15,
            ),
          ),
          if (report != null && report.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'PHOTOS FROM THE REPORT',
              style: AppTextStyles.personnelChip,
            ),
            const SizedBox(height: 8),
            ProofThumbnails(urls: report.photoUrls),
          ],
          if (report != null) ...[
            const SizedBox(height: 12),
            _ReportedBy(report: report),
          ],
        ],
      ),
    );
  }
}

class _ReportedBy extends StatelessWidget {
  const _ReportedBy({required this.report});

  final DamageReport report;

  @override
  Widget build(BuildContext context) => Text(
    'Reported by ${report.reporterName} · '
    '${DateFormat('MMM d, h:mm a').format(report.submittedAt.toLocal())}',
    style: AppTextStyles.personnelCardBody,
  );
}

/// A white card with a title and an optional action in its corner.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.icon,
    this.action,
  });

  final String title;
  final IconData? icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => PersonnelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.personnelCardTitle.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (icon case final glyph?)
              Icon(glyph, color: AppColors.personnelBody, size: 22),
          ],
        ),
        const SizedBox(height: 12),
        child,
        if (action case final button?) ...[const SizedBox(height: 12), button],
      ],
    ),
  );
}

/// The work order's tasks — the admin adds them, the technician ticks
/// them (Objective 5.A).
class _TasksCard extends ConsumerWidget {
  const _TasksCard({required this.workOrder, required this.open});

  final WorkOrder workOrder;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = switch (ref.watch(myTasksProvider)) {
      AsyncData(value: Success(:final value)) => [
        for (final task in value)
          if (task.workOrderId == workOrder.id) task,
      ],
      _ => null,
    };
    final done = tasks
        ?.where((task) => task.status == TaskStatus.completed)
        .length;

    return _Section(
      title: tasks == null
          ? 'Tasks'
          : 'Tasks · ${done ?? 0} of ${tasks.length} done',
      icon: Icons.checklist_rounded,
      child: switch (tasks) {
        null => const LinearProgressIndicator(minHeight: 2),
        [] => const Text(
          'No tasks on this work order.',
          style: AppTextStyles.personnelCardBody,
        ),
        final list => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final task in list) ...[
              TaskTile(task: task, readOnly: !open, opensWorkOrder: false),
              if (task != list.last) const SizedBox(height: 8),
            ],
          ],
        ),
      },
    );
  }
}

/// The materials recorded as used (5.C) — or, once filed, those the
/// report deducted.
class _MaterialsCard extends ConsumerWidget {
  const _MaterialsCard({
    required this.workOrder,
    required this.open,
    required this.latest,
  });

  final WorkOrder workOrder;
  final bool open;
  final AccomplishmentReport? latest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!open) {
      final used = latest?.materialsUsed ?? const <MaterialUsage>[];
      return _Section(
        title: 'Materials Used',
        icon: Icons.inventory_2_outlined,
        child: used.isEmpty
            ? const Text(
                'No materials were recorded.',
                style: AppTextStyles.personnelCardBody,
              )
            : Column(
                children: [
                  for (final material in used)
                    _MaterialRow(
                      name: material.itemName,
                      amount:
                          '${formatQuantity(material.quantityUsed)} '
                          '${material.unitOfMeasurement}',
                    ),
                ],
              ),
      );
    }

    return _Section(
      title: 'Materials Used',
      icon: Icons.inventory_2_outlined,
      action: _GoldOutlineButton(
        icon: Icons.add_shopping_cart_rounded,
        label: 'Record Material',
        onPressed: () =>
            showRecordMaterialSheet(context, workOrderId: workOrder.id),
      ),
      child: AsyncValueView<List<RecordedMaterial>>(
        value: ref.watch(recordedMaterialsProvider(workOrder.id)),
        loadingHeight: 40,
        onRetry: () => ref.invalidate(recordedMaterialsProvider(workOrder.id)),
        isEmpty: (list) => list.isEmpty,
        emptyIcon: Icons.inventory_2_outlined,
        emptyMessage:
            'None yet. Record what you use, or scan its code with the gold '
            'button; it comes off stock when you submit.',
        data: (list) => Column(
          children: [
            for (final material in list)
              _MaterialRow(
                name: material.usage.itemName,
                amount:
                    '${formatQuantity(material.usage.quantityUsed)} '
                    '${material.usage.unitOfMeasurement}',
                onEdit: () => _edit(context, ref, material),
                onRemove: () => _remove(context, ref, material),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    RecordedMaterial material,
  ) async {
    final item = await ref
        .read(inventoryRepositoryProvider)
        .getItemById(material.inventoryItemId);
    if (!context.mounted) return;
    switch (item) {
      case Success(:final value):
        await showRecordMaterialSheet(
          context,
          workOrderId: workOrder.id,
          item: value,
          current: material.usage.quantityUsed,
        );
      case Error(:final failure):
        showPersonnelMessage(context, failure.message, isError: true);
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    RecordedMaterial material,
  ) async {
    final result = await ref
        .read(personnelWorkControllerProvider)
        .removeMaterial(
          workOrderId: workOrder.id,
          inventoryItemId: material.inventoryItemId,
        );
    if (!context.mounted) return;
    reportOutcome(
      context,
      result,
      success: '${material.usage.itemName} removed.',
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.name,
    required this.amount,
    this.onEdit,
    this.onRemove,
  });

  final String name;
  final String amount;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onEdit,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: AppTextStyles.personnelSubtitle.copyWith(
                color: AppColors.personnelTitle,
              ),
            ),
          ),
          Text(
            amount,
            style: AppTextStyles.personnelSubtitle.copyWith(
              color: AppColors.trackingAccentText,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove $name',
              onPressed: onRemove,
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.personnelBody,
              ),
            ),
        ],
      ),
    ),
  );
}

/// The tools borrowed for this work order and still out (5.C).
class _ToolsCard extends ConsumerWidget {
  const _ToolsCard({required this.workOrder, required this.open});

  final WorkOrder workOrder;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = switch (ref.watch(myToolLoansProvider)) {
      AsyncData(value: Success(:final value)) => [
        for (final loan in value)
          if (loan.workOrderId == workOrder.id) loan,
      ],
      _ => null,
    };
    if (!open && (loans == null || loans.isEmpty)) {
      return const SizedBox.shrink();
    }

    return _Section(
      title: 'Tools With You',
      icon: Icons.handyman_outlined,
      action: open
          ? _GoldOutlineButton(
              icon: Icons.add_rounded,
              label: 'Borrow a Tool',
              onPressed: () =>
                  showBorrowToolSheet(context, workOrderId: workOrder.id),
            )
          : null,
      child: switch (loans) {
        null => const LinearProgressIndicator(minHeight: 2),
        [] => const Text(
          'None borrowed for this work order.',
          style: AppTextStyles.personnelCardBody,
        ),
        final list => Column(
          children: [
            for (final loan in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loan.toolName,
                            style: AppTextStyles.personnelSubtitle.copyWith(
                              color: AppColors.personnelTitle,
                            ),
                          ),
                          Text(
                            'Since ${DateFormat('MMM d, h:mm a').format(loan.borrowedAt.toLocal())}',
                            style: AppTextStyles.personnelCardBody,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => showReturnToolSheet(context, loan),
                      child: const Text('Return'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      },
    );
  }
}

/// "Request Additional Materials" in the frame's style: gold outline,
/// full width (Group 42).
class _GoldOutlineButton extends StatelessWidget {
  const _GoldOutlineButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.accentGold,
      side: const BorderSide(color: AppColors.accentGold, width: 2),
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: AppTextStyles.personnelCardTitle.copyWith(fontSize: 15),
    ),
  );
}

/// Photo Evidence, Completion Notes and Mark Complete (Group 42): the
/// accomplishment report (5.B).
class _CompletionForm extends ConsumerStatefulWidget {
  const _CompletionForm({required this.workOrder});

  final WorkOrder workOrder;

  @override
  ConsumerState<_CompletionForm> createState() => _CompletionFormState();
}

class _CompletionFormState extends ConsumerState<_CompletionForm> {
  final _notes = TextEditingController();
  final _photos = <PickedPhoto>[];

  /// Reserved on the first attempt and kept for retries, so a submission
  /// that reached the server is not filed twice.
  String? _reportId;
  bool _busy = false;
  String? _error;

  static const int _maxPhotos = AccomplishmentReportRepositoryImpl.maxPhotos;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final picked = await pickPhotos(
      context,
      ref,
      limit: _maxPhotos - _photos.length,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _photos.addAll(picked.take(_maxPhotos - _photos.length));
      _error = null;
    });
  }

  Future<void> _submit(List<RecordedMaterial> materials, int openTasks) async {
    final notes = _notes.text.trim();
    if (notes.isEmpty || _photos.isEmpty) {
      setState(
        () => _error = notes.isEmpty
            ? 'Describe the work that was done.'
            : 'Add at least one photo of the finished work.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark complete?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your report goes to GSU for sign-off, and the requestor is '
              'told the work is done.',
            ),
            if (materials.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('These come off stock:'),
              for (final material in materials)
                Text(
                  '• ${formatQuantity(material.usage.quantityUsed)} '
                  '${material.usage.unitOfMeasurement} '
                  '${material.usage.itemName}',
                ),
            ],
            if (openTasks > 0) ...[
              const SizedBox(height: 12),
              Text(
                openTasks == 1
                    ? '1 task is not ticked off.'
                    : '$openTasks tasks are not ticked off.',
                style: const TextStyle(color: AppColors.personnelUrgentText),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final reportId = _reportId ??= ref
        .read(accomplishmentReportRepositoryProvider)
        .newReportId();
    final result = await ref
        .read(personnelWorkControllerProvider)
        .submitAccomplishment(
          reportId: reportId,
          workOrderId: widget.workOrder.id,
          completionNotes: notes,
          photos: List.of(_photos),
          materialsUsed: [for (final material in materials) material.usage],
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        showPersonnelMessage(
          context,
          'Report submitted. GSU will review it and sign it off.',
        );
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final materials = switch (ref.watch(
      recordedMaterialsProvider(widget.workOrder.id),
    )) {
      AsyncData(value: Success(:final value)) => value,
      _ => const <RecordedMaterial>[],
    };
    final openTasks = switch (ref.watch(myTasksProvider)) {
      AsyncData(value: Success(:final value)) =>
        value
            .where(
              (task) =>
                  task.workOrderId == widget.workOrder.id &&
                  task.status != TaskStatus.completed,
            )
            .length,
      _ => 0,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'Photo Evidence',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < _photos.length; index++)
                _PickedPhotoTile(
                  photo: _photos[index],
                  onRemove: _busy
                      ? null
                      : () => setState(() => _photos.removeAt(index)),
                ),
              if (_photos.length < _maxPhotos)
                _UploadTile(onTap: _busy ? null : _addPhotos),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Completion Notes',
          child: TextField(
            controller: _notes,
            enabled: !_busy,
            minLines: 4,
            maxLines: 8,
            maxLength: AccomplishmentReportRepositoryImpl.notesLimit,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              hintText: 'Enter completion notes here...',
              filled: true,
              fillColor: AppColors.personnelNotesFill,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_error case final message?) ...[
          const SizedBox(height: 12),
          Text(
            message,
            style: AppTextStyles.personnelCardBody.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : () => _submit(materials, openTasks),
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_rounded),
          label: Text(_busy ? 'Submitting…' : 'Mark Complete'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.textPrimary,
            minimumSize: const Size.fromHeight(56),
            textStyle: AppTextStyles.personnelSection.copyWith(
              color: Colors.white,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class _PickedPhotoTile extends StatelessWidget {
  const _PickedPhotoTile({required this.photo, required this.onRemove});

  final PickedPhoto photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.accentGold, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Image.memory(
            photo.bytes,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              width: 96,
              height: 96,
              child: Icon(Icons.image_outlined),
            ),
          ),
        ),
      ),
      Positioned(
        top: -8,
        right: -8,
        child: IconButton.filled(
          tooltip: 'Remove photo',
          onPressed: onRemove,
          iconSize: 14,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(backgroundColor: AppColors.error),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ),
    ],
  );
}

/// The dashed gold "Upload" tile (Group 42).
class _UploadTile extends StatelessWidget {
  const _UploadTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add a photo',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(
        painter: _DashedBorder(),
        child: SizedBox(
          width: 96,
          height: 96,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_a_photo_outlined,
                color: AppColors.accentGold,
              ),
              const SizedBox(height: 6),
              Text(
                'Upload',
                style: AppTextStyles.personnelCardBody.copyWith(
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accentGold
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The latest accomplishment report filed, and where its review stands
/// (5.B).
class _SubmittedReport extends StatelessWidget {
  const _SubmittedReport({required this.report, required this.workOrder});

  final AccomplishmentReport report;
  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat('MMM d, h:mm a');
    final reviewedAt = report.reviewedAt;
    final verdict = switch ((reviewedAt, workOrder.status)) {
      (null, _) => 'Waiting for GSU to sign it off.',
      (final at?, WorkOrderStatus.completed) =>
        'Signed off ${when.format(at.toLocal())}.',
      (final at?, _) =>
        'Sent back ${when.format(at.toLocal())} — see GSU\'s note above.',
    };

    return _Section(
      title: 'Accomplishment Report',
      icon: Icons.assignment_turned_in_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Submitted ${when.format(report.submittedAt.toLocal())}. $verdict',
            style: AppTextStyles.personnelCardBody,
          ),
          const SizedBox(height: 12),
          Text(
            report.completionNotes,
            style: AppTextStyles.personnelSubtitle.copyWith(
              color: AppColors.personnelTitle,
            ),
          ),
          if (report.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            ProofThumbnails(urls: report.photoUrls),
          ],
        ],
      ),
    );
  }
}
