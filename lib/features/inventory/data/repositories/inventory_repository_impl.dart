import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/inventory_transaction_type.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../models/inventory_item.dart';
import '../models/inventory_transaction.dart';
import 'inventory_repository.dart';

/// Firestore-backed [InventoryRepository].
///
/// The append-only ledger invariant from 1.B is enforced here in code, not
/// merely documented: [recordTransaction] is the only method that writes
/// `quantityAvailable`, and it always writes a matching ledger entry in
/// the same transaction.
class InventoryRepositoryImpl extends FirestoreRepository
    implements InventoryRepository {
  const InventoryRepositoryImpl({required super.db, required super.guard});

  static const String _items = FirestorePaths.inventoryItems;
  static const String _transactions = FirestorePaths.inventoryTransactions;

  @override
  Future<Result<InventoryItem>> getItemById(String id) =>
      getOne(path: _items, id: id, convert: InventoryItem.fromFirestore);

  @override
  Future<Result<InventoryItem>> getItemByQrCode(String qrCode) async {
    final matches = await getMany(
      query: collection(_items).where('qrCode', isEqualTo: qrCode).limit(1),
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
  Stream<Result<List<InventoryItem>>> watchItems({String? category}) {
    Query<Map<String, dynamic>> query = collection(_items);
    if (category != null) {
      query = query.where('category', isEqualTo: category);
    }
    return watchMany(
      query: query.orderBy('name'),
      convert: InventoryItem.fromFirestore,
    );
  }

  @override
  Stream<Result<List<InventoryItem>>> watchLowStockItems() =>
      // Firestore cannot compare two fields of the same document, so
      // "quantityAvailable <= minimumThreshold" has to be evaluated
      // client-side. Acceptable at GSU's scale (a store room, not a
      // warehouse); if the catalogue ever outgrows that, the fix is a
      // denormalized `isLowStock` boolean maintained by the same
      // transaction that moves stock.
      watchMany(
        query: collection(_items),
        convert: InventoryItem.fromFirestore,
      ).map(
        (result) =>
            result.map((items) => items.where((i) => i.isLowStock).toList()),
      );

  @override
  Future<Result<String>> createItem(InventoryItem item) => add(
    path: _items,
    data: {
      ...item.toFirestore(),
      // Opening stock always arrives through a replenishment
      // transaction, so even the first units are traceable.
      'quantityAvailable': 0,
    },
  );

  @override
  Future<Result<void>> updateItemDetails(InventoryItem item) => updateDoc(
    path: _items,
    id: item.id,
    data: {...item.toFirestore(), 'updatedAt': FirestoreRepository.serverNow}
      // Stripped, not trusted: the interface documents that balance
      // changes go through recordTransaction, and silently honouring a
      // balance passed here would bypass the ledger entirely.
      ..remove('quantityAvailable'),
  );

  @override
  Future<Result<InventoryTransaction>> recordTransaction({
    required String inventoryItemId,
    required InventoryTransactionType type,
    required double quantity,
    required String performedBy,
    String? workOrderId,
    String? accomplishmentReportId,
    String? notes,
  }) => db.runTransaction<InventoryTransaction>((transaction) async {
    if (quantity <= 0) {
      throw FirebaseException(
        plugin: 'gsuhub',
        code: 'invalid-argument',
        message: 'Transaction quantity must be greater than zero.',
      );
    }

    final itemRef = collection(_items).doc(inventoryItemId);
    final snapshot = await transaction.get(itemRef);

    if (!snapshot.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'No inventory item $inventoryItemId',
      );
    }

    final item = InventoryItem.fromFirestore(snapshot);
    final before = item.quantityAvailable;
    // The new balance is computed from the value read *inside* this
    // transaction, never from anything the caller supplied — that is what
    // makes concurrent movements safe.
    final after = type.isDeduction ? before - quantity : before + quantity;

    if (after < 0) {
      throw FirebaseException(
        plugin: 'gsuhub',
        code: 'failed-precondition',
        message:
            'Not enough ${item.name} in stock: $before available, '
            '$quantity requested.',
      );
    }

    final performedAt = DateTime.now().toUtc();
    final ledgerRef = collection(_transactions).doc();

    transaction.update(itemRef, {
      'quantityAvailable': after,
      'updatedAt': FirestoreRepository.serverNow,
    });

    transaction.set(ledgerRef, {
      'inventoryItemId': inventoryItemId,
      'itemName': item.name,
      'type': type.id,
      'quantity': quantity,
      'quantityBefore': before,
      'quantityAfter': after,
      'workOrderId': workOrderId,
      'accomplishmentReportId': accomplishmentReportId,
      'notes': notes,
      'performedBy': performedBy,
      'performedAt': Timestamp.fromDate(performedAt),
    });

    return InventoryTransaction(
      id: ledgerRef.id,
      inventoryItemId: inventoryItemId,
      itemName: item.name,
      type: type,
      quantity: quantity,
      quantityBefore: before,
      quantityAfter: after,
      workOrderId: workOrderId,
      accomplishmentReportId: accomplishmentReportId,
      notes: notes,
      performedBy: performedBy,
      performedAt: performedAt,
    );
  });

  @override
  Future<Result<List<InventoryTransaction>>> getTransactionsForItem(
    String inventoryItemId, {
    int limit = 50,
  }) => getMany(
    query: collection(_transactions)
        .where('inventoryItemId', isEqualTo: inventoryItemId)
        .orderBy('performedAt', descending: true)
        .limit(limit),
    convert: InventoryTransaction.fromFirestore,
  );

  @override
  Future<Result<List<InventoryTransaction>>> getTransactionsForWorkOrder(
    String workOrderId,
  ) => getMany(
    query: collection(_transactions)
        .where('workOrderId', isEqualTo: workOrderId)
        .orderBy('performedAt', descending: true),
    convert: InventoryTransaction.fromFirestore,
  );
}
