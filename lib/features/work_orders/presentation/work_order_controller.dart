import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/work_order_status.dart';
import '../../audit/presentation/current_actor_provider.dart';
import '../data/models/work_order.dart';

/// Moves work orders between Kanban columns.
///
/// The move is attempted, not predicted: the repository re-reads the
/// stored status inside a transaction and can refuse. When it does, the
/// reason is shown and the board — which renders from the live stream —
/// simply never changes, so the card appears to snap back.
class WorkOrderController {
  const WorkOrderController(this._ref);

  final Ref _ref;

  Future<void> move({
    required BuildContext context,
    required WorkOrder workOrder,
    required WorkOrderStatus to,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final actor = await _ref.read(currentActorProvider.future);

    if (actor == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Your session has expired. Please sign in again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final result = await _ref
        .read(workOrderRepositoryProvider)
        .setStatus(workOrder.id, to, actor: actor);

    result.fold(
      (_) => messenger.showSnackBar(
        SnackBar(content: Text('${workOrder.title} moved to ${to.title}.')),
      ),
      (failure) => messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      ),
    );
  }
}

final workOrderControllerProvider = Provider(WorkOrderController.new);
