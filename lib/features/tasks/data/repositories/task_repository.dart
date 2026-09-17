import '../../../../core/enums/task_status.dart';
import '../../../../core/utils/result.dart';
import '../models/maintenance_task.dart';

/// Abstract contract for the `tasks` collection — the personnel daily
/// checklist (manuscript Figure 24).
///
/// **Interface only** — implementation is 1.C.
abstract interface class TaskRepository {
  Future<Result<MaintenanceTask>> getById(String id);

  /// Tasks belonging to one work order.
  Stream<Result<List<MaintenanceTask>>> watchByWorkOrder(String workOrderId);

  /// One technician's task list. [dueOn] narrows it to a single day for
  /// the "Today's To-Do" view; omit it for everything outstanding.
  Stream<Result<List<MaintenanceTask>>> watchByAssignee(
    String personnelId, {
    DateTime? dueOn,
    TaskStatus? status,
  });

  Future<Result<String>> create(MaintenanceTask task);

  Future<Result<void>> update(MaintenanceTask task);

  /// Updates task state.
  ///
  /// Implementations must also adjust the assignee's denormalized
  /// `users.activeTaskCount` (via `UserRepository.adjustActiveTaskCount`)
  /// in the same logical operation — that counter has no other writer, and
  /// letting it drift would corrupt the Admin personnel view. See the
  /// denormalization table in docs/data_dictionary.md.
  Future<Result<void>> setStatus(String taskId, TaskStatus status);

  /// Attaches proof-of-work photos ("Upload Proof", Figure 24).
  Future<Result<void>> addProofPhotos({
    required String taskId,
    required List<String> photoUrls,
  });
}
