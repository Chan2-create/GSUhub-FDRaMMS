import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/inventory_transaction_type.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/quantity_format.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_item.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_item_draft.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_transaction.dart';
import 'package:gsuhub/features/inventory/data/repositories/inventory_repository.dart';

import '../../../../core/data/firestore_repository.dart';
import '../../../../core/data/qr_codes.dart';
import '../../../audit/data/repositories/audit_writes.dart';

/// Firestore-backed [InventoryRepository].
///
/// The append-only ledger invariant from 1.B is enforced here in code, not
/// merely documented: every method that writes `quantityAvailable` writes
/// a matching ledger entry in the same transaction.
/// Objective 1 moved this data to Supabase; the app uses [InventoryRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreInventoryRepository extends FirestoreRepository
    implements InventoryRepository {
  const FirestoreInventoryRepository({required super.db, required super.guard});

  static const String _items = FirestorePaths.inventoryItems;
  static const String _transactions = FirestorePaths.inventoryTransactions;

  /// The longest reason a stock count may give.
  static const int reasonLimit = 200;

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
  Stream<Result<InventoryItem>> watchItem(String id) =>
      watchOne(path: _items, id: id, convert: InventoryItem.fromFirestore);

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
  Future<Result<String>> createItem({
    required InventoryItemDraft draft,
    required double openingStock,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    if (openingStock < 0) {
      return const Result.failure(
        ValidationFailure('The opening stock cannot be below zero.'),
      );
    }
    final clean = draft.normalized();
    if (await _codeTaken(clean.qrCode) case final failure?) {
      return Result.failure(failure);
    }

    return db.runTransaction<String>((transaction) async {
      final itemRef = collection(_items).doc();
      transaction.set(itemRef, {
        ...clean.toFields(),
        'quantityAvailable': openingStock,
        'condition': null,
        'createdAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      });
      if (openingStock > 0) {
        _stageEntry(
          transaction,
          itemId: itemRef.id,
          itemName: clean.name,
          type: InventoryTransactionType.replenishment,
          quantity: openingStock,
          before: 0,
          after: openingStock,
          actor: actor,
          notes: 'Opening stock',
        );
      }
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.created,
        entityType: _items,
        entityId: itemRef.id,
        description:
            'Added ${clean.name} to the inventory'
            '${openingStock > 0 ? ' with ${QuantityFormat.withUnit(openingStock, clean.unitOfMeasurement)}' : ''}',
      );
      return itemRef.id;
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
    final clean = draft.normalized();
    if (await _codeTaken(clean.qrCode, exceptId: itemId) case final failure?) {
      return Result.failure(failure);
    }

    return db.runTransaction<void>((transaction) async {
      final itemRef = collection(_items).doc(itemId);
      final snapshot = await transaction.get(itemRef);
      if (!snapshot.exists) {
        throw FirestoreRepository.notFound(
          'This material is no longer in the inventory.',
        );
      }
      final before = snapshot.data() ?? const <String, dynamic>{};
      final fields = clean.toFields();
      final changes = <String, dynamic>{
        for (final MapEntry(:key, :value) in fields.entries)
          if (before[key] != value) key: {'from': before[key], 'to': value},
      };
      if (changes.isEmpty) return;

      transaction.update(itemRef, {
        ...fields,
        'updatedAt': FirestoreRepository.serverNow,
      });
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.updated,
        entityType: _items,
        entityId: itemId,
        description: 'Updated ${clean.name}',
        changes: changes,
      );
    });
  }

  @override
  Future<Result<InventoryTransaction>> recordDelivery({
    required String itemId,
    required double quantity,
    required AuditActor actor,
    String? notes,
  }) => recordTransaction(
    inventoryItemId: itemId,
    type: InventoryTransactionType.replenishment,
    quantity: quantity,
    performedBy: actor.id,
    performedByName: actor.name,
    notes: _orNull(notes),
  );

  @override
  Future<Result<InventoryTransaction>> recordStockCount({
    required String itemId,
    required double countedQuantity,
    required AuditActor actor,
    required String reason,
  }) async {
    final why = reason.trim();
    if (countedQuantity < 0) {
      return const Result.failure(
        ValidationFailure('The count cannot be below zero.'),
      );
    }
    if (why.isEmpty) {
      return const Result.failure(
        ValidationFailure('Say why the count differs.'),
      );
    }
    if (why.length > reasonLimit) {
      return const Result.failure(
        ValidationFailure('Keep the reason to $reasonLimit characters.'),
      );
    }

    return db.runTransaction<InventoryTransaction>((transaction) async {
      final itemRef = collection(_items).doc(itemId);
      final snapshot = await transaction.get(itemRef);
      if (!snapshot.exists) {
        throw FirestoreRepository.notFound(
          'This material is no longer in the inventory.',
        );
      }
      final item = InventoryItem.fromFirestore(snapshot);
      final before = item.quantityAvailable;
      if (countedQuantity == before) {
        throw FirestoreRepository.precondition(
          'The count matches the record: '
          '${QuantityFormat.withUnit(before, item.unitOfMeasurement)}.',
        );
      }

      transaction.update(itemRef, {
        'quantityAvailable': countedQuantity,
        'updatedAt': FirestoreRepository.serverNow,
      });
      return _stageEntry(
        transaction,
        itemId: itemId,
        itemName: item.name,
        type: InventoryTransactionType.adjustment,
        quantity: (countedQuantity - before).abs(),
        before: before,
        after: countedQuantity,
        actor: actor,
        notes: why,
      );
    });
  }

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
  }) async {
    if (quantity <= 0) {
      return const Result.failure(
        ValidationFailure('Enter a quantity above zero.'),
      );
    }

    return db.runTransaction<InventoryTransaction>((transaction) async {
      final itemRef = collection(_items).doc(inventoryItemId);
      final snapshot = await transaction.get(itemRef);

      if (!snapshot.exists) {
        throw FirestoreRepository.notFound(
          'This material is no longer in the inventory.',
        );
      }

      final item = InventoryItem.fromFirestore(snapshot);
      final before = item.quantityAvailable;
      // The new balance is computed from the value read *inside* this
      // transaction, never from anything the caller supplied — that is
      // what makes concurrent movements safe.
      final after = type.isDeduction ? before - quantity : before + quantity;

      if (after < 0) {
        throw FirestoreRepository.precondition(
          'Only ${QuantityFormat.withUnit(before, item.unitOfMeasurement)} '
          'of ${item.name} in stock.',
        );
      }

      transaction.update(itemRef, {
        'quantityAvailable': after,
        'updatedAt': FirestoreRepository.serverNow,
      });
      return _stageEntry(
        transaction,
        itemId: inventoryItemId,
        itemName: item.name,
        type: type,
        quantity: quantity,
        before: before,
        after: after,
        actor: AuditActor(id: performedBy, name: performedByName ?? ''),
        workOrderId: workOrderId,
        accomplishmentReportId: accomplishmentReportId,
        notes: notes,
      );
    });
  }

  @override
  Stream<Result<List<InventoryTransaction>>> watchTransactionsForItem(
    String inventoryItemId, {
    int limit = 100,
  }) => watchMany(
    query: collection(_transactions)
        .where('inventoryItemId', isEqualTo: inventoryItemId)
        .orderBy('performedAt', descending: true)
        .limit(limit),
    convert: InventoryTransaction.fromFirestore,
  );

  @override
  Stream<Result<List<InventoryTransaction>>> watchTransactionsSince(
    DateTime since,
  ) => watchMany(
    query: collection(_transactions)
        .where(
          'performedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(since.toUtc()),
        )
        .orderBy('performedAt', descending: true),
    convert: InventoryTransaction.fromFirestore,
  );

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

  /// Writes one ledger entry, stamped with server time, and returns it as
  /// written (with this device's time standing in for the server's).
  InventoryTransaction _stageEntry(
    Transaction transaction, {
    required String itemId,
    required String itemName,
    required InventoryTransactionType type,
    required double quantity,
    required double before,
    required double after,
    required AuditActor actor,
    String? workOrderId,
    String? accomplishmentReportId,
    String? notes,
  }) {
    final ledgerRef = collection(_transactions).doc();
    final entry = InventoryTransaction(
      id: ledgerRef.id,
      inventoryItemId: itemId,
      itemName: itemName,
      type: type,
      quantity: quantity,
      quantityBefore: before,
      quantityAfter: after,
      workOrderId: workOrderId,
      accomplishmentReportId: accomplishmentReportId,
      notes: notes,
      performedBy: actor.id,
      performedByName: actor.name.isEmpty ? null : actor.name,
      performedAt: DateTime.now().toUtc(),
    );
    transaction.set(ledgerRef, {
      ...entry.toFirestore(),
      'performedAt': FirestoreRepository.serverNow,
    });
    return entry;
  }

  /// A failure saying [code] is taken, or null when it is free.
  Future<Failure?> _codeTaken(String code, {String? exceptId}) async {
    final owner = await guard.call(
      () => qrCodeOwner(db.raw, code, exceptId: exceptId),
    );
    return owner.fold(
      (owner) => owner == null
          ? null
          : ValidationFailure('The code $code is already on $owner.'),
      (failure) => failure,
    );
  }

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
