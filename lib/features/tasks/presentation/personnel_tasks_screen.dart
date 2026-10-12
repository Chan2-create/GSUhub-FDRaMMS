import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/enums/task_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../shells/personnel/personnel_shell.dart';
import '../../user_management/presentation/profile_providers.dart';
import '../../work_orders/presentation/personnel/personnel_providers.dart';
import '../../work_orders/presentation/personnel/widgets/personnel_widgets.dart';
import 'widgets/task_tiles.dart';

/// The Tasks tab (Objective 5.A; manuscript Figure 24, Chris's export
/// Group 39): today's progress, the technician's trade, today's tasks,
/// and those coming up.
class PersonnelTasksScreen extends ConsumerWidget {
  const PersonnelTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trade = switch (ref.watch(signedInProfileProvider).value) {
      Success(:final value) => value.specialization?.assignedPersonnelLabel,
      _ => null,
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, personnelBottomInset(context)),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to Home',
              onPressed: () => context.go(RoutePaths.personnelDashboard),
              icon: const Icon(
                Icons.arrow_back,
                color: AppColors.myReportsTitle,
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              header: true,
              child: const Text(
                'Tasks',
                style: AppTextStyles.personnelGreeting,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AsyncValueView<MyWork>(
          value: ref.watch(myWorkProvider),
          loadingHeight: 300,
          onRetry: () => ref
            ..invalidate(myWorkOrdersProvider)
            ..invalidate(myTasksProvider),
          data: (work) {
            final done = work.today
                .where((task) => task.status == TaskStatus.completed)
                .length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Progress(done: done, total: work.today.length),
                if (trade != null) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: PersonnelChip(
                      trade,
                      background: AppColors.sidebarBackground,
                      foreground: Colors.white,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const PersonnelSectionTitle('Today'),
                const SizedBox(height: 12),
                if (work.today.isEmpty)
                  const PersonnelCard(
                    child: Text(
                      'Nothing is due today.',
                      style: AppTextStyles.personnelCardBody,
                    ),
                  )
                else
                  for (final task in work.today) ...[
                    TaskTile(
                      task: task,
                      workOrder: work.workOrders[task.workOrderId],
                    ),
                    const SizedBox(height: 12),
                  ],
                if (work.upcoming.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const PersonnelSectionTitle('Coming up'),
                  const SizedBox(height: 12),
                  for (final task in work.upcoming) ...[
                    TaskTile(
                      task: task,
                      workOrder: work.workOrders[task.workOrderId],
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// "Tasks Completed — 3 of 5 Tasks — 60%" with its bar (Group 39).
class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : done / total;
    return PersonnelCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Semantics(
        label: '$done of $total tasks completed today',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tasks Completed',
              style: AppTextStyles.personnelTileLabel,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$done of $total Tasks',
                    style: AppTextStyles.personnelGreeting.copyWith(
                      fontSize: 24,
                    ),
                  ),
                ),
                Text(
                  '${(fraction * 100).round()}%',
                  style: AppTextStyles.personnelGreeting.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 10,
                color: AppColors.textPrimary,
                backgroundColor: AppColors.ratingCommentFill,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
