import '../../../../core/data/row_snapshot.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/allocated_material.dart';
import 'material_allocation_repository.dart';

/// Supabase-backed [MaterialAllocationRepository] (Objective 1): what GSU
/// sets aside for a work order, directly or by approving a request (6.B).
/// Setting materials aside moves no stock.
class MaterialAllocationRepositoryImpl extends SupabaseRepository
    implements MaterialAllocationRepository {
  const MaterialAllocationRepositoryImpl({
    required super.client,
    required super.guard,
  });

  static const String _table = 'work_order_materials_allocated';

  @override
  Stream<Result<List<AllocatedMaterial>>> watchForWorkOrder(
    String workOrderId,
  ) => guard.stream(
    client
        .from(_table)
        .stream(primaryKey: const ['work_order_id', 'inventory_item_id'])
        .eq('work_order_id', workOrderId)
        .map(
          (rows) =>
              [
                for (final row in rows)
                  AllocatedMaterial.fromFirestore(
                    RowSnapshot.fromKeyedRow(
                      row,
                      idColumn: 'inventory_item_id',
                    ),
                  ),
              ]..sort(
                (a, b) => a.line.itemName.toLowerCase().compareTo(
                  b.line.itemName.toLowerCase(),
                ),
              ),
        ),
  );

  @override
  Future<Result<void>> allocate({
    required String workOrderId,
    required String inventoryItemId,
    required double quantity,
    required AuditActor actor,
  }) => rpc('allocate_material', {
    'work_order_id': workOrderId,
    'inventory_item_id': inventoryItemId,
    'quantity': quantity,
  });

  @override
  Future<Result<void>> remove({
    required String workOrderId,
    required String inventoryItemId,
    required AuditActor actor,
  }) => rpc('remove_allocation', {
    'work_order_id': workOrderId,
    'inventory_item_id': inventoryItemId,
  });
}
