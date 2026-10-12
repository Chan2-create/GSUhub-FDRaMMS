import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../shells/personnel/personnel_shell.dart';
import '../../data/models/work_order.dart';
import 'personnel_providers.dart';
import 'widgets/personnel_widgets.dart';

/// My Work Orders (Objective 5.A; manuscript Figure 25, Chris's export
/// Group 41): every work order assigned to the technician, as a list or
/// as a board with a column per status.
class MyWorkOrdersScreen extends ConsumerStatefulWidget {
  const MyWorkOrdersScreen({super.key});

  @override
  ConsumerState<MyWorkOrdersScreen> createState() => _MyWorkOrdersScreenState();
}

class _MyWorkOrdersScreenState extends ConsumerState<MyWorkOrdersScreen> {
  bool _board = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
        child: Row(
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
            Semantics(
              header: true,
              child: const Text(
                'My Work Orders',
                style: AppTextStyles.personnelGreeting,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: _ViewToggle(
          board: _board,
          onChanged: (board) => setState(() => _board = board),
        ),
      ),
      Expanded(
        child: AsyncValueView<List<WorkOrder>>(
          value: ref.watch(myWorkOrdersProvider),
          onRetry: () => ref.invalidate(myWorkOrdersProvider),
          isEmpty: (orders) => orders.isEmpty,
          emptyIcon: Icons.assignment_outlined,
          emptyMessage:
              'No work orders yet. Work GSU assigns to you appears here.',
          data: (orders) =>
              _board ? _Board(orders: orders) : _List(orders: orders),
        ),
      ),
    ],
  );
}

/// List View / Board View (Group 41).
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.board, required this.onChanged});

  final bool board;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.personnelToggleTrack,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final (label, value) in [
            ('List View', false),
            ('Board View', true),
          ])
            Expanded(
              child: Semantics(
                button: true,
                selected: board == value,
                child: Material(
                  color: board == value ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: board == value ? null : () => onChanged(value),
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(
                          label,
                          style: AppTextStyles.personnelCardTitle.copyWith(
                            fontSize: 14,
                            fontWeight: board == value
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: board == value
                                ? AppColors.personnelTitle
                                : AppColors.personnelBody,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Open work first (in progress, pending, awaiting sign-off), then
/// completed; newest first within each.
List<WorkOrder> _ordered(List<WorkOrder> orders) {
  int rank(WorkOrderStatus status) => switch (status) {
    WorkOrderStatus.inProgress => 0,
    WorkOrderStatus.pending => 1,
    WorkOrderStatus.forReview => 2,
    WorkOrderStatus.completed => 3,
  };
  return [...orders]..sort((a, b) {
    final byStatus = rank(a.status).compareTo(rank(b.status));
    return byStatus != 0 ? byStatus : b.createdAt.compareTo(a.createdAt);
  });
}

class _List extends StatelessWidget {
  const _List({required this.orders});

  final List<WorkOrder> orders;

  @override
  Widget build(BuildContext context) {
    final sorted = _ordered(orders);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 0, 16, personnelBottomInset(context)),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          WorkOrderCard(workOrder: sorted[index], showStatus: true),
    );
  }
}

/// A column per status, scrolled sideways (Group 41).
class _Board extends StatelessWidget {
  const _Board({required this.orders});

  final List<WorkOrder> orders;

  @override
  Widget build(BuildContext context) => ListView(
    scrollDirection: Axis.horizontal,
    padding: EdgeInsets.fromLTRB(16, 0, 16, personnelBottomInset(context)),
    children: [
      for (final status in WorkOrderStatus.values) ...[
        _Column(
          status: status,
          orders: [
            for (final order in _ordered(orders))
              if (order.status == status) order,
          ],
        ),
        const SizedBox(width: 12),
      ],
    ],
  );
}

class _Column extends StatelessWidget {
  const _Column({required this.status, required this.orders});

  final WorkOrderStatus status;
  final List<WorkOrder> orders;

  @override
  Widget build(BuildContext context) => Container(
    width: 300,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.personnelColumn,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                workStatusLabel(status),
                style: AppTextStyles.personnelCardTitle,
              ),
            ),
            PersonnelChip(
              '${orders.length}',
              background: AppColors.personnelToggleTrack,
              foreground: AppColors.homeSectionTitle,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: orders.isEmpty
              ? const Text('None.', style: AppTextStyles.personnelCardBody)
              : ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      WorkOrderCard(workOrder: orders[index]),
                ),
        ),
      ],
    ),
  );
}

/// A work order as My Work Orders draws it (Group 41): its number, place,
/// description, trade and priority, and when it was assigned.
class WorkOrderCard extends StatelessWidget {
  const WorkOrderCard({
    required this.workOrder,
    super.key,
    this.showStatus = false,
  });

  final WorkOrder workOrder;

  /// The list shows each card's status; on the board the column says it.
  final bool showStatus;

  @override
  Widget build(BuildContext context) => PersonnelCard(
    onTap: () => context.push(RoutePaths.personnelWorkOrderFor(workOrder.id)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DisplayId.workOrder(workOrder.id),
                style: AppTextStyles.personnelWorkOrderId,
              ),
            ),
            if (showStatus)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: workStatusColor(workOrder.status),
                      border: Border.all(color: AppColors.personnelBody),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    workStatusLabel(workOrder.status),
                    style: AppTextStyles.personnelCardBody.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          [?workOrder.facilityName, workOrder.title].join(' - '),
          style: AppTextStyles.personnelCardTitle,
        ),
        const SizedBox(height: 4),
        Text(
          workOrder.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.personnelCardBody,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PersonnelChip(
              workOrder.category.label,
              background: AppColors.personnelWorkOrderCard,
              foreground: AppColors.personnelChip,
            ),
            PriorityTag(workOrder.priority),
          ],
        ),
        const Divider(height: 24),
        Row(
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 16,
              color: AppColors.personnelBody,
            ),
            const SizedBox(width: 6),
            Text(
              'Assigned: ${DateFormat('MMM d').format(workOrder.createdAt.toLocal())}'
              '${workOrder.scheduledFor == null ? '' : ' · Due ${DateFormat('MMM d').format(workOrder.scheduledFor!.toLocal())}'}',
              style: AppTextStyles.personnelCardBody,
            ),
          ],
        ),
      ],
    ),
  );
}
