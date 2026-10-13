import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/task_status.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../work_orders/data/models/work_order.dart';
import '../../../work_orders/presentation/personnel/personnel_work_controller.dart';
import '../../../work_orders/presentation/personnel/widgets/personnel_widgets.dart';
import '../../data/models/maintenance_task.dart';
import '../../domain/task_day.dart';

/// Ticking a task and uploading its proof, shared by every task tile
/// (Objective 5.A).
mixin _TaskActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;

  MaintenanceTask get task;

  /// Done, or back from done: to in progress when it has proof, to do
  /// otherwise.
  Future<void> toggle() async {
    final next = task.status == TaskStatus.completed
        ? (task.proofPhotoUrls.isEmpty
              ? TaskStatus.pending
              : TaskStatus.inProgress)
        : TaskStatus.completed;
    setState(() => busy = true);
    final result = await ref
        .read(personnelWorkControllerProvider)
        .setTaskStatus(task.id, next);
    if (!mounted) return;
    setState(() => busy = false);
    reportOutcome(context, result);
  }

  Future<void> uploadProof() async {
    final photos = await pickPhotos(context, ref, limit: 3);
    if (photos == null || !mounted) return;
    setState(() => busy = true);
    final result = await ref
        .read(personnelWorkControllerProvider)
        .uploadProof(task.id, photos);
    if (!mounted) return;
    setState(() => busy = false);
    reportOutcome(context, result, success: 'Proof uploaded.');
  }

  void openWorkOrder() =>
      context.push(RoutePaths.personnelWorkOrderFor(task.workOrderId));
}

/// The tick at a task's left: an empty gold ring to do, a ring with a dot
/// in progress, a filled gold check when done (Figure 24).
class TaskCheck extends StatelessWidget {
  const TaskCheck({
    required this.status,
    required this.onTap,
    super.key,
    this.size = 26,
  });

  final TaskStatus status;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final done = status == TaskStatus.completed;
    // A node of its own: merged into the card, a screen reader could not
    // tell the tick from the card it sits on, nor tap it.
    return Semantics(
      container: true,
      button: true,
      checked: done,
      label: done ? 'Mark as not done' : 'Mark as done',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: size,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.accentGold : Colors.transparent,
                border: Border.all(color: AppColors.accentGold, width: 2),
              ),
              child: switch (status) {
                TaskStatus.completed => const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                TaskStatus.inProgress => Center(
                  child: Container(
                    width: size / 2.4,
                    height: size / 2.4,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accentGold,
                    ),
                  ),
                ),
                TaskStatus.pending => null,
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A task as the Tasks tab and a work order's page list it (Group 39):
/// its tick, title, where, the trade, proof photos, and Upload Proof.
class TaskTile extends ConsumerStatefulWidget {
  const TaskTile({
    required this.task,
    super.key,
    this.workOrder,
    this.readOnly = false,
    this.opensWorkOrder = true,
  });

  final MaintenanceTask task;

  /// The task's work order, for where and which trade; null while loading.
  final WorkOrder? workOrder;

  /// Shown, not changed: its work order was submitted or signed off.
  final bool readOnly;

  /// Tapping the card opens the work order — not on that work order's own
  /// page.
  final bool opensWorkOrder;

  @override
  ConsumerState<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends ConsumerState<TaskTile>
    with _TaskActions<TaskTile> {
  @override
  MaintenanceTask get task => widget.task;

  @override
  Widget build(BuildContext context) {
    final done = task.status == TaskStatus.completed;
    final workOrder = widget.workOrder;
    final where = task.description ?? workOrder?.facilityName;
    final overdue = TaskDay.isOverdue(task, DateTime.now());

    final readOnly = widget.readOnly;
    return PersonnelCard(
      color: done ? AppColors.trackingNoteFill : Colors.white,
      edge: task.status == TaskStatus.inProgress ? AppColors.accentGold : null,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
      onTap: widget.opensWorkOrder ? openWorkOrder : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaskCheck(
            status: task.status,
            onTap: busy || readOnly ? null : toggle,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Text(
                  task.title,
                  style: AppTextStyles.personnelCardTitle.copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? AppColors.personnelBody : null,
                  ),
                ),
                if (where != null) ...[
                  const SizedBox(height: 4),
                  Text(where, style: AppTextStyles.personnelCardBody),
                ],
                if (workOrder != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    workOrder.category.label,
                    style: AppTextStyles.personnelCardBody.copyWith(
                      color: AppColors.accentGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (overdue) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Overdue — was due '
                    '${DateFormat('MMM d').format(task.dueDate!.toLocal())}',
                    style: AppTextStyles.personnelCardBody.copyWith(
                      color: AppColors.personnelUrgentText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (!done && !readOnly) ...[
                  const SizedBox(height: 10),
                  UploadProofButton(onPressed: busy ? null : uploadProof),
                ],
                if (task.proofPhotoUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ProofThumbnails(urls: task.proofPhotoUrls),
                ],
                if (done && task.proofPhotoUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const PersonnelChip(
                    'Proof submitted',
                    background: AppColors.sidebarBackground,
                    foreground: Colors.white,
                  ),
                ],
                if (busy) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A task on the dashboard's Today's To-Do (Group 47): gold-edged while
/// open, pale and struck through once done.
class TodoTile extends ConsumerStatefulWidget {
  const TodoTile({required this.task, super.key, this.workOrder});

  final MaintenanceTask task;
  final WorkOrder? workOrder;

  @override
  ConsumerState<TodoTile> createState() => _TodoTileState();
}

class _TodoTileState extends ConsumerState<TodoTile>
    with _TaskActions<TodoTile> {
  @override
  MaintenanceTask get task => widget.task;

  @override
  Widget build(BuildContext context) {
    final done = task.status == TaskStatus.completed;
    final workOrder = widget.workOrder;
    final detail = task.description ?? workOrder?.title;

    return PersonnelCard(
      color: done ? AppColors.personnelDoneCard : Colors.white,
      edge: done ? null : AppColors.personnelHighlight,
      padding: const EdgeInsets.fromLTRB(4, 8, 14, 14),
      onTap: openWorkOrder,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaskCheck(status: task.status, size: 22, onTap: busy ? null : toggle),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 11),
                Text(
                  task.title,
                  style: AppTextStyles.personnelCardTitle.copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? AppColors.personnelBody : null,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.personnelCardBody,
                  ),
                ],
                if (!done) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // The chip takes the room the button leaves, so a
                      // long damage type wraps no sooner than it must.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: workOrder == null
                              ? null
                              : PersonnelChip(workOrder.category.label),
                        ),
                      ),
                      const SizedBox(width: 8),
                      UploadProofButton(onPressed: busy ? null : uploadProof),
                    ],
                  ),
                ],
                if (busy) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small square photos in a row, each opening full size.
class ProofThumbnails extends StatelessWidget {
  const ProofThumbnails({required this.urls, super.key, this.size = 64});

  final List<String> urls;
  final double size;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final url in urls)
        Semantics(
          container: true,
          button: true,
          label: 'Open photo',
          child: GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: InteractiveViewer(
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.accentGold, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.network(
                  url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => SizedBox(
                    width: size,
                    height: size,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.personnelBody,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
