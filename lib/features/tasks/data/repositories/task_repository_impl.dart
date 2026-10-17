import '../../../../core/data/supabase_repository.dart';
import '../../../../core/enums/task_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/maintenance_task.dart';
import 'task_repository.dart';

/// Supabase-backed [TaskRepository] (Objective 1).
///
/// The task functions (supabase/migrations/*_task_functions.sql) change a
/// task only while its work is open; the first one a technician touches
/// starts the work order, its reports and the requestor's timeline with
/// it.
class TaskRepositoryImpl extends SupabaseRepository implements TaskRepository {
  const TaskRepositoryImpl({required super.client, required super.guard});

  static const String _table = 'tasks';

  /// Longest task title and description accepted.
  static const int titleLimit = 120;
  static const int descriptionLimit = 500;

  /// Soonest due first; tasks with no due date last; then oldest first.
  static List<MaintenanceTask> sorted(List<MaintenanceTask> tasks) =>
      [...tasks]..sort((a, b) {
        final ad = a.dueDate;
        final bd = b.dueDate;
        if (ad != null && bd != null) {
          final byDue = ad.compareTo(bd);
          if (byDue != 0) return byDue;
        } else if (ad != null) {
          return -1;
        } else if (bd != null) {
          return 1;
        }
        return a.createdAt.compareTo(b.createdAt);
      });

  @override
  Future<Result<MaintenanceTask>> getById(String id) =>
      getOne(table: _table, id: id, convert: MaintenanceTask.fromFirestore);

  @override
  Stream<Result<List<MaintenanceTask>>> watchByWorkOrder(String workOrderId) =>
      watchMany(
        stream: client
            .from(_table)
            .stream(primaryKey: const ['id'])
            .eq('work_order_id', workOrderId),
        convert: MaintenanceTask.fromFirestore,
      ).map((result) => result.map(sorted));

  /// A task stays with the technician it was given to, so a stream
  /// filtered on them never misses one.
  @override
  Stream<Result<List<MaintenanceTask>>> watchByAssignee(String personnelId) =>
      watchMany(
        stream: client
            .from(_table)
            .stream(primaryKey: const ['id'])
            .eq('assigned_to', personnelId),
        convert: MaintenanceTask.fromFirestore,
      ).map((result) => result.map(sorted));

  @override
  Future<Result<String>> addTask({
    required String workOrderId,
    required String title,
    required AuditActor actor,
    String? description,
    DateTime? dueDate,
  }) =>
      // Once: a retry after a task that landed would add it twice.
      rpcOnce<String>('add_task', {
        'work_order_id': workOrderId,
        'title': title,
        'description': description,
        'due_date': SupabaseRepository.time(dueDate),
      });

  @override
  Future<Result<void>> deleteTask({
    required String taskId,
    required AuditActor actor,
  }) => rpc('delete_task', {'task_id': taskId});

  @override
  Future<Result<void>> setStatus({
    required String taskId,
    required TaskStatus status,
    required AuditActor actor,
  }) => rpc('set_task_status', {'task_id': taskId, 'status': status.id});

  @override
  Future<Result<void>> addProofPhotos({
    required String taskId,
    required List<String> photoUrls,
    required AuditActor actor,
  }) => rpc('add_proof_photos', {'task_id': taskId, 'photo_urls': photoUrls});
}
