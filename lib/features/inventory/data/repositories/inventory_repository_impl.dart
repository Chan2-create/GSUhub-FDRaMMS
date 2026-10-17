import '../../../../core/data/row_snapshot.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/enums/inventory_transaction_type.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/inventory_item.dart';
import '../models/inventory_item_draft.dart';
import '../models/inventory_transaction.dart';
import 'inventory_repository.dart';

/// Supabase-backed [InventoryRepository] (Objective 1).
///
/// The append-only ledger is enforced by the database itself: no account,
/// administrators and the database owner included, can change a quantity
/// except by writing a ledger entry, which works out the balances and
/// moves the stock (supabase/migrations/*_stock_ledger.sql). This class
/// never sends a quantity, only movements.
class InventoryRepositoryImpl extends SupabaseRepository
    implements InventoryRepository {
  const InventoryRepositoryImpl({required super.client, required super.guard});

  static const String _items = 'inventory_items';
  static const String _transactions = 'inventory_transactions';

  /// The longest reason a stock count may give.
  static const int reasonLimit = 200;

  @override
  Future<Result<InventoryItem>> getItemById(String id) =>
      getOne(table: _items, id: id, convert: InventoryItem.fromFirestore);

  @override
  Future<Result<InventoryItem>> getItemByQrCode(String qrCode) async {
    final matches = await getMany(
      query: client.from(_items).select().eq('qr_code', qrCode).limit(1),
      convert: InventoryItem.fromFirestore,
    );
    return matches.fold(
      (list) => list.isEmpty
          ? const Result<InventoryItem>.failure(
              NotFoundFailure('No inventory item matches that code.'),
            )
          : Result.success(list.first),
      Result.failure,
    );
  }

  @override
  Stream<Result<List<InventoryItem>>> watchItems({String? category}) =>
      // Filtered here: a material's category can change.
      watchMany(
        stream: client
            .from(_items)
            .stream(primaryKey: const ['id'])
            .order('name', ascending: true),
        convert: InventoryItem.fromFirestore,
      ).map(
        (result) => result.map(
          (items) => [
            for (final item in items)
              if (category == null || item.category == category) item,
          ],
        ),
      );

  @override
  Stream<Result<InventoryItem>> watchItem(String id) =>
      watchOne(table: _items, id: id, convert: InventoryItem.fromFirestore);

  @override
  Stream<Result<List<InventoryItem>>> watchLowStockItems() => watchItems().map(
    (result) =>
        result.map((items) => items.where((i) => i.isLowStock).toList()),
  );

  @override
  Future<Result<String>> createItem({
    required InventoryItemDraft draft,
    required double openingStock,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    // Once: a retry after a material that landed would add it twice.
    return rpcOnce<String>('create_inventory_item', {
      ..._fields(draft),
      'opening_stock': openingStock,
    });
  }

  @override
  Future<Result<void>> updateItemDetails({
    required String itemId,
    required InventoryItemDraft draft,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    return rpc('update_inventory_item', {'id': itemId, ..._fields(draft)});
  }

  @override
  Future<Result<InventoryTransaction>> recordDelivery({
    required String itemId,
    required double quantity,
    required AuditActor actor,
    String? notes,
  }) => rpcRow(
    'record_delivery',
    {'item_id': itemId, 'quantity': quantity, 'notes': notes},
    convert: InventoryTransaction.fromFirestore,
    // A retry after a delivery that landed would receive it twice.
    once: true,
  );

  @override
  Future<Result<InventoryTransaction>> recordStockCount({
    required String itemId,
    required double countedQuantity,
    required AuditActor actor,
    required String reason,
  }) => rpcRow(
    'record_stock_count',
    {'item_id': itemId, 'counted_quantity': countedQuantity, 'reason': reason},
    convert: InventoryTransaction.fromFirestore,
    once: true,
  );

  /// Movements go through the operation that makes them: a delivery, a
  /// count, a filed accomplishment report.
  @override
  Future<Result<InventoryTransaction>> recordTransaction({
    required String inventoryItemId,
    required InventoryTransactionType type,
    required double quantity,
    required String performedBy,
    String? performedByName,
    String? workOrderId,
    String? accomplishmentReportId,
    String? notes,
  }) => SupabaseRepository.unsupported('InventoryRepository.recordTransaction');

  @override
  Stream<Result<List<InventoryTransaction>>> watchTransactionsForItem(
    String inventoryItemId, {
    int limit = 100,
  }) => watchMany(
    stream: client
        .from(_transactions)
        .stream(primaryKey: const ['id'])
        .eq('inventory_item_id', inventoryItemId)
        .order('performed_at')
        .limit(limit),
    convert: InventoryTransaction.fromFirestore,
  );

  /// The ledger never changes an entry, so a stream filtered on its time
  /// misses nothing.
  @override
  Stream<Result<List<InventoryTransaction>>> watchTransactionsSince(
    DateTime since,
  ) => watchMany(
    stream: client
        .from(_transactions)
        .stream(primaryKey: const ['id'])
        .gte('performed_at', SupabaseRepository.time(since)!)
        .order('performed_at'),
    convert: InventoryTransaction.fromFirestore,
  );

  @override
  Future<Result<List<InventoryTransaction>>> getTransactionsForItem(
    String inventoryItemId, {
    int limit = 50,
  }) => getMany(
    query: client
        .from(_transactions)
        .select()
        .eq('inventory_item_id', inventoryItemId)
        .order('performed_at')
        .limit(limit),
    convert: InventoryTransaction.fromFirestore,
  );

  @override
  Future<Result<List<InventoryTransaction>>> getTransactionsForWorkOrder(
    String workOrderId,
  ) => getMany(
    query: client
        .from(_transactions)
        .select()
        .eq('work_order_id', workOrderId)
        .order('performed_at'),
    convert: InventoryTransaction.fromFirestore,
  );

  /// The draft as the database functions take it.
  static Map<String, Object?> _fields(InventoryItemDraft draft) {
    final fields = draft.toFields();
    return {
      for (final MapEntry(:key, :value) in fields.entries)
        RowSnapshot.columnFor(key): value,
    };
  }
}
