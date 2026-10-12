import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/recorded_material.dart';

/// The materials a technician records as used on a work order while the
/// work is under way (Objective 5.C). Deducted from stock only when the
/// accomplishment report is submitted (§3.4).
abstract interface class MaterialUsageRepository {
  /// What is recorded on [workOrderId], by item name.
  Stream<Result<List<RecordedMaterial>>> watchForWorkOrder(String workOrderId);

  /// Records [quantity] of [inventoryItemId] as used on [workOrderId],
  /// replacing any quantity recorded for it before. Refused unless [actor]
  /// is assigned, the work is not yet submitted, and there is that much in
  /// stock.
  Future<Result<void>> record({
    required String workOrderId,
    required String inventoryItemId,
    required double quantity,
    required AuditActor actor,
  });

  /// Takes [inventoryItemId] off what is recorded on [workOrderId].
  Future<Result<void>> remove({
    required String workOrderId,
    required String inventoryItemId,
  });
}
