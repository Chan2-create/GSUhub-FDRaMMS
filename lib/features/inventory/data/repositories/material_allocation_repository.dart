import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/allocated_material.dart';

/// The materials GSU pre-assigns to a work order (Objective 6.B, Group 43's
/// "Pre-assigned Materials"). Setting them aside moves no stock: only what
/// the technician records as used comes off, when the accomplishment
/// report is filed (§1.5).
abstract interface class MaterialAllocationRepository {
  /// What is pre-assigned to [workOrderId], by item name.
  Stream<Result<List<AllocatedMaterial>>> watchForWorkOrder(String workOrderId);

  /// Sets the quantity of [inventoryItemId] pre-assigned to [workOrderId],
  /// replacing any set before. Refused once the work order is no longer
  /// open, or when the store holds less.
  Future<Result<void>> allocate({
    required String workOrderId,
    required String inventoryItemId,
    required double quantity,
    required AuditActor actor,
  });

  /// Takes [inventoryItemId] off what is pre-assigned to [workOrderId].
  Future<Result<void>> remove({
    required String workOrderId,
    required String inventoryItemId,
    required AuditActor actor,
  });
}
