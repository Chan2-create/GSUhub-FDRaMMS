import '../../../../core/enums/inventory_transaction_type.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/inventory_item.dart';
import '../models/inventory_item_draft.dart';
import '../models/inventory_transaction.dart';

/// Abstract contract for the `inventory_items` collection and its
/// append-only `inventory_transactions` ledger.
///
/// **The append-only invariant is enforced by this contract's shape.**
/// There is deliberately no `updateTransaction` and no `deleteTransaction`
/// method, and no way to write `quantityAvailable` directly — every path
/// that changes stock writes the ledger entry and the new balance
/// together. A caller cannot move stock without leaving a trace, because
/// no method exists that would let them.
abstract interface class InventoryRepository {
  Future<Result<InventoryItem>> getItemById(String id);

  /// Resolves a scanned material barcode or QR code (§1.5).
  Future<Result<InventoryItem>> getItemByQrCode(String qrCode);

  Stream<Result<List<InventoryItem>>> watchItems({String? category});

  /// One material, live: its card's details and stock.
  Stream<Result<InventoryItem>> watchItem(String id);

  /// Items at or below their configured minimum threshold, backing the
  /// automatic low-stock alerts (§1.5) and the Admin "Low Stock Alerts"
  /// tile (Figure 15).
  Stream<Result<List<InventoryItem>>> watchLowStockItems();

  /// Registers a new material (Objective 6.A). Its [openingStock], when
  /// above zero, arrives as a `replenishment` entry in the same write, so
  /// even the first units are traceable. Refused when another material,
  /// tool, room or piece of equipment carries the same code.
  Future<Result<String>> createItem({
    required InventoryItemDraft draft,
    required double openingStock,
    required AuditActor actor,
  });

  /// Saves a material's details. Never touches its stock.
  Future<Result<void>> updateItemDetails({
    required String itemId,
    required InventoryItemDraft draft,
    required AuditActor actor,
  });

  /// Stock received into the GSU store: Figure 15's cart and ORDER
  /// buttons (Objective 6.A). A `replenishment` entry.
  Future<Result<InventoryTransaction>> recordDelivery({
    required String itemId,
    required double quantity,
    required AuditActor actor,
    String? notes,
  });

  /// A physical count that differs from the record: an `adjustment`
  /// entry that brings the balance to [countedQuantity], with the
  /// [reason]. Refused when the count matches.
  Future<Result<InventoryTransaction>> recordStockCount({
    required String itemId,
    required double countedQuantity,
    required AuditActor actor,
    required String reason,
  });

  /// The general way to change stock on hand.
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
    String? performedByName,
    String? workOrderId,
    String? accomplishmentReportId,
    String? notes,
  });

  /// Ledger history for one item, newest first, live (§3.4:
  /// administrators can "review material usage history").
  Stream<Result<List<InventoryTransaction>>> watchTransactionsForItem(
    String inventoryItemId, {
    int limit = 100,
  });

  /// Every movement since [since], newest first: what the analytics'
  /// most-used materials and the inventory export read (Objective 6.C).
  Stream<Result<List<InventoryTransaction>>> watchTransactionsSince(
    DateTime since,
  );

  /// Ledger history for one item, newest first.
  Future<Result<List<InventoryTransaction>>> getTransactionsForItem(
    String inventoryItemId, {
    int limit = 50,
  });

  /// Ledger entries raised against one work order.
  Future<Result<List<InventoryTransaction>>> getTransactionsForWorkOrder(
    String workOrderId,
  );
}
