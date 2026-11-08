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

  /// Work orders assigned to one technician, newest first, backing the
  /// personnel app's "My Work Orders" list and board views (Figure 25).
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
  /// - read the report and require it to be `approved`, classified, with
  ///   its official priority confirmed (Objective 4.C), and without a work
  ///   order already;
  /// - read the person and require an active maintenance-personnel account;
  /// - create the work order as `pending`, carrying the report's category,
  ///   priority and facility, and [scheduledFor] as its target date;
  /// - move the report to `assigned` and link it to the work order;
  /// - increment the person's `activeTaskCount` atomically;
  /// - create the work order's first task, the job itself, due on
  ///   [scheduledFor] or today, and notify the technician (Objective 5.A);
  /// - append audit entries for the report and the work order.
  Future<Result<String>> assignFromReport({
    required String reportId,
    required String personnelId,
    required AuditActor actor,
    DateTime? scheduledFor,
  });

  /// Starts a work order: Pending to In Progress, the one move made
  /// directly (Objective 7.B). The rest belong to the accomplishment
  /// report: submitting it sends the work for review, and its review
  /// completes the work or sends it back. Implementations refuse those
  /// here, saying where they are made, so the Kanban board cannot skip the
  /// sign-off.
  ///
  /// Implementations must, in one transaction:
  /// - reject transitions `WorkOrderStatus.canTransitionTo` disallows,
  ///   reading the stored status rather than trusting the caller;
  /// - move every linked report to the matching `ReportStatus`, through
  ///   its own transition guard — a report whose status cannot follow
  ///   aborts the move rather than leaving the two disagreeing;
  /// - append an audit entry naming [actor].
  Future<Result<void>> setStatus(
    String workOrderId,
    WorkOrderStatus status, {
    required AuditActor actor,
  });

  /// Hands open work to another technician (Objective 7.A; manuscript
  /// §3.4: "Modify report priorities and assignments when necessary").
  ///
  /// Implementations must, in one transaction:
  /// - refuse work that is not pending or in progress, a person who is not
  ///   an active technician, and the technician who already holds it;
  /// - name [personnelId] alone on the work order, and hand them its
  ///   unfinished tasks;
  /// - move the open-work counts, never below zero;
  /// - record the change in each linked report's history, with the new
  ///   technician, and tell the requestor, the new technician and the one
  ///   it was taken from;
  /// - append an audit entry naming [actor].
  Future<Result<void>> reassign({
    required String workOrderId,
    required String personnelId,
    required AuditActor actor,
  });

  /// Takes a completed work order off the board, or puts it back
  /// (2026-11-08). Work orders are never deleted: archiving leaves the
  /// status and the history as they are, and the technician still sees it.
  Future<Result<void>> setArchived({
    required String workOrderId,
    required bool archived,
    required AuditActor actor,
  });

  /// Sets or clears the administrator's note to the technician, shown at
  /// the top of the work order in the personnel app (Figure 25).
  Future<Result<void>> updateAdminNotes({
    required String workOrderId,
    required String? notes,
    required AuditActor actor,
  });
}
