import '../../../../core/enums/task_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/maintenance_task.dart';

/// Abstract contract for the `tasks` collection — the personnel daily
/// checklist (manuscript Figure 24; Objective 5.A).
///
/// An administrator adds tasks to a work order, for the technician it is
/// assigned to; assigning the work order creates its first one (Chris's
/// decision, 2026-10-12). The technician works through them — progress,
/// proof photos, done — while the work order is open.
///
/// Tasks do not touch `users.activeTaskCount`: since 2.B that counts the
/// open **work orders** a person holds, which is what the console's
/// workload columns show.
abstract interface class TaskRepository {
  Future<Result<MaintenanceTask>> getById(String id);

  /// Tasks belonging to one work order, soonest due first.
  Stream<Result<List<MaintenanceTask>>> watchByWorkOrder(String workOrderId);

  /// One technician's tasks, every status, soonest due first. The daily
  /// views pick their day from these.
  Stream<Result<List<MaintenanceTask>>> watchByAssignee(String personnelId);

  /// Adds a task to [workOrderId] for its assigned technician, and tells
  /// them (administrator). Refused for a work order that is submitted or
  /// completed, or has nobody assigned.
  Future<Result<String>> addTask({
    required String workOrderId,
    required String title,
    required AuditActor actor,
    String? description,
    DateTime? dueDate,
  });

  /// Removes a task that is not done yet (administrator).
  Future<Result<void>> deleteTask({
    required String taskId,
    required AuditActor actor,
  });

  /// Moves a task (technician). A task of a work order not yet started
  /// starts it: the first task touched means the work has begun. Refused
  /// once the work order is submitted or completed.
  Future<Result<void>> setStatus({
    required String taskId,
    required TaskStatus status,
    required AuditActor actor,
  });

  /// Attaches proof-of-work photos ("Upload Proof", Figure 24). A pending
  /// task becomes in progress, and its work order starts, as for
  /// [setStatus].
  Future<Result<void>> addProofPhotos({
    required String taskId,
    required List<String> photoUrls,
    required AuditActor actor,
  });
}
