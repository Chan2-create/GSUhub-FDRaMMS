import '../../../../core/enums/work_order_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
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

  /// Raises a work order from one approved report and assigns it to one
  /// maintenance person (Task Assignment, Objective 2.B). Returns the new
  /// work order's id.
  ///
  /// Implementations must do all of this in one transaction, so a failure
  /// anywhere leaves nothing half-assigned:
  /// - read the report and require it to be `approved`, classified, and
  ///   without a work order already;
  /// - read the person and require an active maintenance-personnel account;
  /// - create the work order as `pending`, carrying the report's category,
  ///   priority and facility, and [scheduledFor] as its target date;
  /// - move the report to `assigned` and link it to the work order;
  /// - increment the person's `activeTaskCount` atomically;
  /// - append audit entries for the report and the work order.
  Future<Result<String>> assignFromReport({
    required String reportId,
    required String personnelId,
    required AuditActor actor,
    DateTime? scheduledFor,
  });

  /// Moves a work order between Kanban columns.
  ///
  /// Implementations must, in one transaction:
  /// - reject transitions `WorkOrderStatus.canTransitionTo` disallows,
  ///   reading the stored status rather than trusting the caller;
  /// - move every linked report to the matching `ReportStatus`, through
  ///   its own transition guard — a report whose status cannot follow
  ///   aborts the move rather than leaving the two disagreeing;
  /// - release the assignees' `activeTaskCount` on completion;
  /// - append an audit entry naming [actor].
  Future<Result<void>> setStatus(
    String workOrderId,
    WorkOrderStatus status, {
    required AuditActor actor,
  });

  /// Assigns personnel (Figure 18). Replaces the existing assignment set.
  Future<Result<void>> assignPersonnel({
    required String workOrderId,
    required List<String> personnelIds,
    required String assignedBy,
  });
}
