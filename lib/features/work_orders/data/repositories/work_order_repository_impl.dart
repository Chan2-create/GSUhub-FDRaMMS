import '../../../../core/data/supabase_repository.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/work_order.dart';
import 'work_order_repository.dart';

/// Supabase-backed [WorkOrderRepository] (Objective 1). Persistence only.
///
/// Raising and moving a work order are work order functions
/// (supabase/migrations/*_work_order_functions.sql): each checks the
/// stored state, moves the reports with it, keeps the technicians'
/// open-work counts, and writes the notices and audit entries.
class WorkOrderRepositoryImpl extends SupabaseRepository
    implements WorkOrderRepository {
  const WorkOrderRepositoryImpl({required super.client, required super.guard});

  static const String _table = 'work_orders';

  @override
  Future<Result<WorkOrder>> getById(String id) =>
      getOne(table: _table, id: id, convert: WorkOrder.fromFirestore);

  @override
  Stream<Result<WorkOrder>> watchById(String id) =>
      watchOne(table: _table, id: id, convert: WorkOrder.fromFirestore);

  @override
  Stream<Result<List<WorkOrder>>> watchAll({
    WorkOrderStatus? status,
    String? categoryId,
  }) =>
      // Filtered here: a work order's status changes, and Realtime never
      // tells a stream filtered on it about one that has moved on.
      _watchVisible().map(
        (result) => result.map(
          (orders) => [
            for (final order in orders)
              if ((status == null || order.status == status) &&
                  (categoryId == null || order.category.id == categoryId))
                order,
          ],
        ),
      );

  @override
  Stream<Result<List<WorkOrder>>> watchByAssignee(String personnelId) =>
      // A technician sees only their own work orders anyway (row level
      // security); an administrator asking about one person sees theirs.
      _watchVisible().map(
        (result) => result.map(
          (orders) => [
            for (final order in orders)
              if (order.assignedPersonnelIds.contains(personnelId)) order,
          ],
        ),
      );

  /// Every work order the caller may see, newest first.
  Stream<Result<List<WorkOrder>>> _watchVisible() => watchMany(
    stream: client
        .from(_table)
        .stream(primaryKey: const ['id'])
        .order('created_at'),
    convert: WorkOrder.fromFirestore,
  );

  @override
  Future<Result<String>> create(WorkOrder workOrder) =>
      SupabaseRepository.unsupported('WorkOrderRepository.create');

  @override
  Future<Result<void>> update(WorkOrder workOrder) =>
      SupabaseRepository.unsupported('WorkOrderRepository.update');

  @override
  Future<Result<String>> assignFromReport({
    required String reportId,
    required String personnelId,
    required AuditActor actor,
    DateTime? scheduledFor,
  }) =>
      // Once: a retry after an assignment that landed would be refused
      // ("already assigned") and hide that it worked.
      rpcOnce<String>('assign_work_order', {
        'report_id': reportId,
        'personnel_id': personnelId,
        'scheduled_for': SupabaseRepository.time(scheduledFor),
      });

  @override
  Future<Result<void>> setStatus(
    String workOrderId,
    WorkOrderStatus status, {
    required AuditActor actor,
  }) =>
      // Safe to retry: moving to the status it already has is a no-op.
      rpc('set_work_order_status', {
        'work_order_id': workOrderId,
        'to_status': status.id,
      });

  @override
  Future<Result<void>> updateAdminNotes({
    required String workOrderId,
    required String? notes,
    required AuditActor actor,
  }) =>
      rpc('update_admin_notes', {'work_order_id': workOrderId, 'notes': notes});
}
