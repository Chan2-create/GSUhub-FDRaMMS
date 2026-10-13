import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/material_line.dart';
import '../models/material_request.dart';

/// Technicians' requests for more materials, and GSU's answers (Objective
/// 6.B; §3.4 "request and monitor materials assigned to work orders").
abstract interface class MaterialRequestRepository {
  /// A fresh id to file a request under, reserved before submitting so a
  /// retry after a timeout cannot file it twice.
  String newRequestId();

  /// A work order's requests, newest first. Personnel pass [requestedBy]
  /// (their own uid): the rules let them list nothing else.
  Stream<Result<List<MaterialRequest>>> watchForWorkOrder(
    String workOrderId, {
    String? requestedBy,
  });

  /// The newest requests across all work orders, for the console.
  Stream<Result<List<MaterialRequest>>> watchRecent({int limit = 50});

  /// Files a request as [actor], who must be assigned to the work order,
  /// while it is open. Names and units are read from the inventory, not
  /// taken from [items]; repeated items are added together. Filing the
  /// same [requestId] again does nothing.
  Future<Result<void>> submit({
    required String requestId,
    required String workOrderId,
    required List<MaterialLine> items,
    required AuditActor actor,
    String? note,
  });

  /// Grants a pending request: its items join the work order's
  /// pre-assigned materials, and the technician is told. Refused when the
  /// work order is no longer open or the store has less than asked.
  Future<Result<void>> approve({
    required String requestId,
    required AuditActor actor,
    String? note,
  });

  /// Refuses a pending request with [note], which the technician sees.
  Future<Result<void>> decline({
    required String requestId,
    required AuditActor actor,
    required String note,
  });
}
