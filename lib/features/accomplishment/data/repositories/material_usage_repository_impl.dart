import '../../../../core/data/row_snapshot.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/recorded_material.dart';
import 'material_usage_repository.dart';

/// Supabase-backed [MaterialUsageRepository] (Objective 1): what a
/// technician records as used on their work, deducted from stock when the
/// accomplishment report is filed.
class MaterialUsageRepositoryImpl extends SupabaseRepository
    implements MaterialUsageRepository {
  const MaterialUsageRepositoryImpl({
    required super.client,
    required super.guard,
  });

  static const String _table = 'work_order_materials_used';

  @override
  Stream<Result<List<RecordedMaterial>>> watchForWorkOrder(
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
                  RecordedMaterial.fromFirestore(
                    RowSnapshot.fromKeyedRow(
                      row,
                      idColumn: 'inventory_item_id',
                    ),
                  ),
              ]..sort(
                (a, b) => a.usage.itemName.toLowerCase().compareTo(
                  b.usage.itemName.toLowerCase(),
                ),
              ),
        ),
  );

  @override
  Future<Result<void>> record({
    required String workOrderId,
    required String inventoryItemId,
    required double quantity,
    required AuditActor actor,
  }) =>
      // Safe to retry: it sets the amount, it does not add to it.
      rpc('record_material_use', {
        'work_order_id': workOrderId,
        'inventory_item_id': inventoryItemId,
        'quantity': quantity,
      });

  @override
  Future<Result<void>> remove({
    required String workOrderId,
    required String inventoryItemId,
  }) => rpc('remove_material_use', {
    'work_order_id': workOrderId,
    'inventory_item_id': inventoryItemId,
  });
}
