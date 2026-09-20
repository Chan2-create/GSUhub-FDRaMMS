import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/initials.dart';
import '../../../../core/widgets/priority_chip.dart';
import '../../../user_management/presentation/personnel_providers.dart';
import '../../data/models/work_order.dart';
import '../work_order_controller.dart';

/// The four-column board (Figma `234:694`).
///
/// Cards move by drag, or by the menu on the card — dragging is not
/// reachable from a keyboard, and this is an internal tool someone will
/// operate all day.
///
/// Whether a move is legal is decided by the repository, not here. A
/// rejected move leaves the card where it was and says why.
class KanbanBoard extends ConsumerWidget {
  const KanbanBoard({required this.columns, super.key});

  final Map<WorkOrderStatus, List<WorkOrder>> columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final status in WorkOrderStatus.values) ...[
            _Column(status: status, workOrders: columns[status] ?? const []),
            const SizedBox(width: 24),
          ],
        ],
      ),
    ),
  );
}

class _Column extends ConsumerStatefulWidget {
  const _Column({required this.status, required this.workOrders});

  final WorkOrderStatus status;
  final List<WorkOrder> workOrders;

  @override
  ConsumerState<_Column> createState() => _ColumnState();
}

class _ColumnState extends ConsumerState<_Column> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => DragTarget<WorkOrder>(
    onWillAcceptWithDetails: (details) {
      final accepts = details.data.status != widget.status;
      if (accepts) setState(() => _hovering = true);
      return accepts;
    },
    onLeave: (_) => setState(() => _hovering = false),
    onAcceptWithDetails: (details) {
      setState(() => _hovering = false);
      ref
          .read(workOrderControllerProvider)
          .move(context: context, workOrder: details.data, to: widget.status);
    },
    builder: (context, candidate, rejected) => Container(
      width: 300,
      constraints: const BoxConstraints(minHeight: 400),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        border: Border.all(
          color: _hovering ? AppColors.primary : AppColors.borderStrong,
          width: _hovering ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.status.title,
                    style: AppTextStyles.kanbanColumnTitle.copyWith(
                      color: widget.status == WorkOrderStatus.completed
                          ? AppColors.primary
                          : null,
                    ),
                  ),
                ),
                _CountBadge(
                  status: widget.status,
                  count: widget.workOrders.length,
                ),
              ],
            ),
          ),
          if (widget.workOrders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Nothing here',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textFaint,
                  ),
                ),
              ),
            )
          else
            for (final workOrder in widget.workOrders)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DraggableCard(workOrder: workOrder),
              ),
        ],
      ),
    ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.status, required this.count});

  final WorkOrderStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      WorkOrderStatus.inProgress => (
        AppColors.highlightAmber,
        AppColors.accentOlive,
      ),
      WorkOrderStatus.completed => (
        AppColors.statusInProgressBackground,
        AppColors.primary,
      ),
      _ => (AppColors.badgeNeutral, AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count',
        style: AppTextStyles.kanbanCount.copyWith(color: foreground),
      ),
    );
  }
}

class _DraggableCard extends StatelessWidget {
  const _DraggableCard({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context) {
    final card = WorkOrderCard(workOrder: workOrder);

    // A completed work order is terminal — there is nowhere for it to go.
    if (workOrder.status == WorkOrderStatus.completed) return card;

    return Draggable<WorkOrder>(
      data: workOrder,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 274, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}

/// One work order (Figma `234:703`).
class WorkOrderCard extends ConsumerWidget {
  const WorkOrderCard({required this.workOrder, super.key});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCompleted = workOrder.status == WorkOrderStatus.completed;
    final names = ref.watch(personnelNamesProvider);
    final assignees = workOrder.assignedPersonnelIds
        .map((id) => names[id])
        .whereType<String>()
        .join(', ');

    return Opacity(
      opacity: isCompleted ? 0.8 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              offset: Offset(0, 1),
              blurRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    DisplayId.workOrder(workOrder.id),
                    style: AppTextStyles.workOrderId.copyWith(
                      color: isCompleted ? AppColors.textSecondary : null,
                      decoration: isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                PriorityChip(level: workOrder.priority, dense: true),
                if (!isCompleted) _MoveMenu(workOrder: workOrder),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              workOrder.title,
              style: AppTextStyles.workOrderTitle.copyWith(
                color: isCompleted ? AppColors.textSecondary : null,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SvgPicture.asset(
                  'assets/icons/location_pin.svg',
                  width: 9.33,
                  height: 11.67,
                  colorFilter: ColorFilter.mode(
                    isCompleted ? AppColors.textFaint : AppColors.textSecondary,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    workOrder.facilityName ?? 'Location not recorded',
                    style: AppTextStyles.workOrderMeta.copyWith(
                      color: isCompleted ? AppColors.textFaint : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                if (assignees.isEmpty)
                  SvgPicture.asset(
                    'assets/icons/unassigned.svg',
                    width: 12.83,
                    height: 9.33,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textFaint,
                      BlendMode.srcIn,
                    ),
                  )
                else
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceControl,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      initialsOf(assignees),
                      style: AppTextStyles.badgeText.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    assignees.isEmpty ? 'Unassigned' : assignees,
                    style: AppTextStyles.workOrderMeta.copyWith(
                      color: isCompleted ? AppColors.textFaint : null,
                      fontStyle: assignees.isEmpty ? FontStyle.italic : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    workOrder.category.label,
                    style: AppTextStyles.badgeText.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Keyboard- and screen-reader-reachable equivalent of dragging.
class _MoveMenu extends ConsumerWidget {
  const _MoveMenu({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = WorkOrderStatus.values
        .where(workOrder.status.canTransitionTo)
        .toList();

    if (targets.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<WorkOrderStatus>(
      tooltip: 'Move work order',
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.more_horiz, size: 16),
      padding: EdgeInsets.zero,
      onSelected: (status) => ref
          .read(workOrderControllerProvider)
          .move(context: context, workOrder: workOrder, to: status),
      itemBuilder: (context) => [
        for (final status in targets)
          PopupMenuItem(value: status, child: Text('Move to ${status.title}')),
      ],
    );
  }
}
