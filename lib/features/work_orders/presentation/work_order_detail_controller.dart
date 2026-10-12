import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../accomplishment/data/models/accomplishment_report.dart';
import '../../audit/data/models/audit_actor.dart';
import '../../audit/presentation/current_actor_provider.dart';
import '../../tasks/data/models/maintenance_task.dart';
import '../../tools/data/models/tool_loan.dart';
import '../data/models/work_order.dart';

/// What the console's work-order page reads (Objective 5): the work order,
/// its tasks, the accomplishment reports filed against it, and the tool
/// loans made for it — all live.

final workOrderDetailProvider = StreamProvider.autoDispose
    .family<Result<WorkOrder>, String>(
      (ref, id) => ref.watch(workOrderRepositoryProvider).watchById(id),
    );

final workOrderTasksProvider = StreamProvider.autoDispose
    .family<Result<List<MaintenanceTask>>, String>(
      (ref, id) => ref.watch(taskRepositoryProvider).watchByWorkOrder(id),
    );

final workOrderAccomplishmentsProvider = StreamProvider.autoDispose
    .family<Result<List<AccomplishmentReport>>, String>(
      (ref, id) => ref
          .watch(accomplishmentReportRepositoryProvider)
          .watchByWorkOrder(id),
    );

final workOrderLoansProvider = StreamProvider.autoDispose
    .family<Result<List<ToolLoan>>, String>(
      (ref, id) => ref.watch(toolRepositoryProvider).watchLoansForWorkOrder(id),
    );

/// The administrator's actions on a work order's page (Objective 5):
/// tasks, the note to the technician, and the review of the work.
class WorkOrderDetailController {
  const WorkOrderDetailController(this._ref);

  final Ref _ref;

  Future<Result<void>> addTask({
    required String workOrderId,
    required String title,
    String? description,
    DateTime? dueDate,
  }) => _act(
    (actor) async => switch (await _ref
        .read(taskRepositoryProvider)
        .addTask(
          workOrderId: workOrderId,
          title: title,
          description: description,
          dueDate: dueDate,
          actor: actor,
        )) {
      Success() => const Result.success(null),
      Error(:final failure) => Result.failure(failure),
    },
  );

  Future<Result<void>> deleteTask(String taskId) => _act(
    (actor) => _ref
        .read(taskRepositoryProvider)
        .deleteTask(taskId: taskId, actor: actor),
  );

  Future<Result<void>> saveNote(String workOrderId, String? note) => _act(
    (actor) => _ref
        .read(workOrderRepositoryProvider)
        .updateAdminNotes(workOrderId: workOrderId, notes: note, actor: actor),
  );

  /// Signs the work off ([approve]) or sends it back with [note].
  Future<Result<void>> review({
    required String reportId,
    required bool approve,
    String? note,
  }) => _act(
    (actor) => _ref
        .read(accomplishmentReportRepositoryProvider)
        .review(reportId: reportId, approve: approve, actor: actor, note: note),
  );

  Future<Result<void>> _act(
    Future<Result<void>> Function(AuditActor actor) action,
  ) async {
    final actor = await _ref.read(currentActorProvider.future);
    if (actor == null) {
      return const Result.failure(
        PermissionFailure('Your session has expired. Please sign in again.'),
      );
    }
    return action(actor);
  }
}

final workOrderDetailControllerProvider = Provider(
  WorkOrderDetailController.new,
);
