import '../../../../core/enums/work_order_status.dart';
import '../../../../core/utils/result.dart';
import '../models/work_order.dart';

/// Abstract contract for the `work_orders` collection.
///
/// **Interface only** — implementation is 1.C.
abstract interface class WorkOrderRepository {
  Future<Result<WorkOrder>> getById(String id);

  Stream<Result<WorkOrder>> watchById(String id);

  /// Admin Kanban board feed (manuscript Figure 19). Grouping by status
  /// is the caller's job; this returns the full filtered set.
  Stream<Result<List<WorkOrder>>> watchAll({
    WorkOrderStatus? status,
    String? categoryId,
  });

  /// Work orders assigned to one technician, backing the personnel app's
  /// "My Work Orders" list and board views (Figure 25).
  Stream<Result<List<WorkOrder>>> watchByAssignee(String personnelId);

  /// Raises a work order from one or more approved reports. [reportIds]
  /// carries more than one entry when duplicates were merged (§3.4).
  Future<Result<String>> create(WorkOrder workOrder);

  Future<Result<void>> update(WorkOrder workOrder);

  /// Moves a work order between Kanban columns. Implementations must
  /// reject transitions that `WorkOrderStatus.canTransitionTo` disallows,
  /// rather than trusting the caller.
  Future<Result<void>> setStatus(String workOrderId, WorkOrderStatus status);

  /// Assigns personnel (Figure 18). Replaces the existing assignment set.
  Future<Result<void>> assignPersonnel({
    required String workOrderId,
    required List<String> personnelIds,
    required String assignedBy,
  });
}
