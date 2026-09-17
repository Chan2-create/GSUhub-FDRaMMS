import '../../../../core/enums/inventory_transaction_type.dart';
import '../../../../core/utils/result.dart';
import '../models/inventory_item.dart';
import '../models/inventory_transaction.dart';

/// Abstract contract for the `inventory_items` collection and its
/// append-only `inventory_transactions` ledger.
///
/// **The append-only invariant is enforced by this contract's shape.**
/// There is deliberately no `updateTransaction` and no `deleteTransaction`
/// method, and no way to write `quantityAvailable` directly — the only
/// path to changing stock is [recordTransaction], which writes the ledger
/// entry and the new balance together. A caller cannot move stock without
/// leaving a trace, because no method exists that would let them.
///
/// **Interface only** — implementation is 1.C.
abstract interface class InventoryRepository {
  Future<Result<InventoryItem>> getItemById(String id);

  /// Resolves a scanned material barcode or QR code (§1.5).
  Future<Result<InventoryItem>> getItemByQrCode(String qrCode);

  Stream<Result<List<InventoryItem>>> watchItems({String? category});

  /// Items at or below their configured minimum threshold, backing the
  /// automatic low-stock alerts (§1.5) and the Admin "Low Stock Alerts"
  /// tile (Figure 15).
  Stream<Result<List<InventoryItem>>> watchLowStockItems();

  /// Registers a new material. Does not set an opening balance — stock
  /// arrives through a `replenishment` transaction, so even the first
  /// units are traceable.
  Future<Result<String>> createItem(InventoryItem item);

  /// Updates an item's descriptive fields (name, category, unit, storage
  /// location, QR code, minimum threshold).
  ///
  /// Implementations **must ignore** any change to `quantityAvailable`
  /// passed here; balance changes go through [recordTransaction] only.
  Future<Result<void>> updateItemDetails(InventoryItem item);

  /// The single supported way to change stock on hand.
  ///
  /// Writes the ledger entry and the item's new `quantityAvailable`
  /// atomically. Implementations must compute the new balance inside the
  /// transaction from the balance they read there — never from a value the
  /// caller supplies — so concurrent movements cannot overwrite each
  /// other.
  ///
  /// Fails with a `ValidationFailure` if a deduction would drive the
  /// balance below zero.
  Future<Result<InventoryTransaction>> recordTransaction({
    required String inventoryItemId,
    required InventoryTransactionType type,
    required double quantity,
    required String performedBy,
    String? workOrderId,
    String? accomplishmentReportId,
    String? notes,
  });

  /// Ledger history for one item, newest first (§3.4: administrators can
  /// "review material usage history").
  Future<Result<List<InventoryTransaction>>> getTransactionsForItem(
    String inventoryItemId, {
    int limit = 50,
  });

  /// Ledger entries raised against one work order.
  Future<Result<List<InventoryTransaction>>> getTransactionsForWorkOrder(
    String workOrderId,
  );
}
