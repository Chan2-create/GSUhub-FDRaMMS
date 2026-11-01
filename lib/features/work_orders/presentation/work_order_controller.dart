import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/work_order_status.dart';
import '../../../core/routing/route_paths.dart';
import '../../audit/presentation/current_actor_provider.dart';
import '../data/models/work_order.dart';

/// Moves work orders between Kanban columns.
///
/// Only one move is made from the board itself: starting the work, Pending
/// to In Progress (Objective 7.B). The others belong to the accomplishment
/// report, as the database insists (supabase/migrations/
/// *_work_order_signoff.sql): the technician sends work for review by
/// submitting it, and the administrator completes the work or sends it
/// back by reviewing it. So a card dropped on Completed, or back on In
/// Progress from For Review, opens its work order at the report to review;
/// one dropped on For Review is refused with the reason. Before 7.B the
/// board could complete work nobody had signed off.
///
/// The start is attempted, not predicted: the database re-reads the
/// stored status and can refuse. When it does, the reason is shown and the
/// board — which renders from the live stream — never changes, so the
/// card appears to snap back.
class WorkOrderController {
  const WorkOrderController(this._ref);

  final Ref _ref;

  Future<void> move({
    required BuildContext context,
    required WorkOrder workOrder,
    required WorkOrderStatus to,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    if (workOrder.status == WorkOrderStatus.forReview &&
        (to == WorkOrderStatus.completed || to == WorkOrderStatus.inProgress)) {
      review(context, workOrder, sendBack: to == WorkOrderStatus.inProgress);
      return;
    }
    if (to == WorkOrderStatus.forReview) {
      _refuse(
        messenger,
        'Work goes to For Review when its technician submits the '
        'accomplishment report.',
      );
      return;
    }
    if (to == WorkOrderStatus.completed) {
      _refuse(
        messenger,
        'Sign off the accomplishment report to complete this work order. '
        'It is reviewed once the technician has submitted it.',
      );
      return;
    }

    final actor = await _ref.read(currentActorProvider.future);
    if (actor == null) {
      _refuse(messenger, 'Your session has expired. Please sign in again.');
      return;
    }

    final result = await _ref
        .read(workOrderRepositoryProvider)
        .setStatus(workOrder.id, to, actor: actor);

    result.fold(
      (_) => messenger.showSnackBar(
        SnackBar(content: Text('${workOrder.title} moved to ${to.title}.')),
      ),
      (failure) => _refuse(messenger, failure.message),
    );
  }

  /// Opens [workOrder] at its accomplishment report, to sign it off or,
  /// given [sendBack], send it back with a note.
  void review(
    BuildContext context,
    WorkOrder workOrder, {
    bool sendBack = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sendBack
              ? 'Send the work back from its accomplishment report, with a '
                    'note for the technician.'
              : 'Review the accomplishment report, then sign it off.',
        ),
      ),
    );
    GoRouter.of(context).go(RoutePaths.adminWorkOrderDetailFor(workOrder.id));
  }

  /// A newer message replaces one still showing: two quick drops should
  /// not leave the second reason queued behind the first.
  static void _refuse(ScaffoldMessengerState messenger, String message) =>
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
}

final workOrderControllerProvider = Provider(WorkOrderController.new);
