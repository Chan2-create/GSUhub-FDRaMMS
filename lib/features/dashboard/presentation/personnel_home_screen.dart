import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../shells/personnel/personnel_shell.dart';
import '../../tasks/presentation/widgets/task_tiles.dart';
import '../../user_management/presentation/profile_providers.dart';
import '../../work_orders/data/models/work_order.dart';
import '../../work_orders/presentation/personnel/personnel_providers.dart';
import '../../work_orders/presentation/personnel/widgets/personnel_widgets.dart';

/// The personnel app's home (Objective 5.A; manuscript Figure 24, Chris's
/// export Group 47): a greeting, the day's numbers, today's to-do, and the
/// technician's open work orders.
class PersonnelHomeScreen extends ConsumerWidget {
  const PersonnelHomeScreen({super.key});

  /// "Good morning" before noon, "Good afternoon" before six, "Good
  /// evening" after.
  static String greetingFor(DateTime now) => switch (now.hour) {
    < 12 => 'Good morning',
    < 18 => 'Good afternoon',
    _ => 'Good evening',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = switch (ref.watch(signedInProfileProvider).value) {
      Success(:final value) => value.fullName,
      _ => null,
    };
    final work = ref.watch(myWorkProvider);
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(myWorkOrdersProvider)
          ..invalidate(myTasksProvider);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, personnelBottomInset(context)),
        children: [
          Text(
            name == null ? greetingFor(now) : '${greetingFor(now)}, $name',
            style: AppTextStyles.personnelGreeting,
          ),
          const SizedBox(height: 4),
          const Text(
            "Ready to tackle today's maintenance?",
            style: AppTextStyles.personnelSubtitle,
          ),
          const SizedBox(height: 20),
          AsyncValueView<MyWork>(
            value: work,
            loadingHeight: 300,
            onRetry: () => ref
              ..invalidate(myWorkOrdersProvider)
              ..invalidate(myTasksProvider),
            data: (work) => _Body(work: work, now: now),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.work, required this.now});

  final MyWork work;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final open = [
      for (final order in work.workOrders.values)
        if (MyWork.isOpen(order.status)) order,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: "Today's Tasks",
                value: work.today.length,
                highlighted: true,
                onTap: () => context.go(RoutePaths.personnelTasks),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: 'Pending Work',
                value: work.pendingWork,
                onTap: () => context.push(RoutePaths.personnelWorkOrders),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: 'Completed',
                value: work.completedWork,
                onTap: () => context.push(RoutePaths.personnelWorkOrders),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        PersonnelSectionTitle(
          "Today's To-Do",
          trailing: Text(
            DateFormat('MMM d, y').format(now),
            style: AppTextStyles.personnelCardBody,
          ),
        ),
        const SizedBox(height: 12),
        if (work.today.isEmpty)
          const _Empty('Nothing is due today. New tasks appear here.')
        else
          for (final task in work.today) ...[
            TodoTile(task: task, workOrder: work.workOrders[task.workOrderId]),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 16),
        PersonnelSectionTitle(
          'My Work Orders',
          trailing: TextButton(
            onPressed: () => context.push(RoutePaths.personnelWorkOrders),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.trackingAccentText,
            ),
            child: const Text('View all'),
          ),
        ),
        const SizedBox(height: 8),
        if (open.isEmpty)
          const _Empty('No open work orders. New ones appear here.')
        else
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: open.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  _WorkOrderCard(workOrder: open[index]),
            ),
          ),
      ],
    );
  }
}

/// One of the three numbers at the top (Group 47).
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.onTap,
    this.highlighted = false,
  });

  final String label;
  final int value;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label: $value',
    excludeSemantics: true,
    child: Material(
      color: highlighted
          ? AppColors.personnelHighlight
          : AppColors.personnelTile,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 104,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  style: AppTextStyles.personnelTileLabel.copyWith(
                    color: highlighted
                        ? AppColors.trackingAccentText
                        : AppColors.personnelBody,
                  ),
                ),
                const Spacer(),
                Text('$value', style: AppTextStyles.personnelTileValue),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A navy card in the My Work Orders row (Group 47).
class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 236,
    child: Material(
      color: AppColors.personnelWorkOrderCard,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push(RoutePaths.personnelWorkOrderFor(workOrder.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DisplayId.workOrder(workOrder.id),
                style: AppTextStyles.personnelWorkOrderId.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                [?workOrder.facilityName, workOrder.title].join(' - '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.personnelCardTitle.copyWith(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: workStatusColor(workOrder.status),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    workStatusLabel(workOrder.status),
                    style: AppTextStyles.personnelCardBody.copyWith(
                      color: AppColors.personnelHighlight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => PersonnelCard(
    child: Text(message, style: AppTextStyles.personnelCardBody),
  );
}
