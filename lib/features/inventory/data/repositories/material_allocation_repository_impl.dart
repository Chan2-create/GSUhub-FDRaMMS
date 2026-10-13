import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/quantity_format.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../../../work_orders/data/models/work_order.dart';
import '../models/allocated_material.dart';
import '../models/inventory_item.dart';
import '../models/material_line.dart';
import 'material_allocation_repository.dart';

/// Firestore-backed [MaterialAllocationRepository], over each work order's
/// `materials_allocated` subcollection.
class MaterialAllocationRepositoryImpl extends FirestoreRepository
    implements MaterialAllocationRepository {
  const MaterialAllocationRepositoryImpl({
    required super.db,
    required super.guard,
  });

  CollectionReference<Map<String, dynamic>> _allocated(String workOrderId) =>
      allocatedMaterials(db.raw, workOrderId);

  /// `work_orders/{workOrderId}/materials_allocated`, for the request
  /// repository's approval, which writes here too.
  static CollectionReference<Map<String, dynamic>> allocatedMaterials(
    FirebaseFirestore firestore,
    String workOrderId,
  ) => firestore
      .collection(FirestorePaths.workOrders)
      .doc(workOrderId)
      .collection(FirestorePaths.materialsAllocated);

  /// Reads [workOrderId] in [transaction] and refuses unless it can still
  /// take materials: pending or in progress.
  static Future<WorkOrder> readOpenWorkOrder(
    Transaction transaction,
    FirebaseFirestore firestore,
    String workOrderId,
  ) async {
    final snapshot = await transaction.get(
      firestore.collection(FirestorePaths.workOrders).doc(workOrderId),
    );
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound('No work order $workOrderId');
    }
    final workOrder = WorkOrder.fromFirestore(snapshot);
    if (workOrder.status != WorkOrderStatus.pending &&
        workOrder.status != WorkOrderStatus.inProgress) {
      throw FirestoreRepository.precondition(
        '${DisplayId.workOrder(workOrderId)} is '
        '${workOrder.status.title}; materials can no longer be assigned to '
        'it.',
      );
    }
    return workOrder;
  }

  @override
  Stream<Result<List<AllocatedMaterial>>> watchForWorkOrder(
    String workOrderId,
  ) =>
      watchMany(
        query: _allocated(workOrderId),
        convert: AllocatedMaterial.fromFirestore,
      ).map(
        (result) => result.map(
          (materials) => [...materials]
            ..sort(
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
  }) async {
    if (quantity <= 0) {
      return const Result.failure(
        ValidationFailure('Enter how much to set aside.'),
      );
    }

    return db.runTransaction<void>((transaction) async {
      await readOpenWorkOrder(transaction, db.raw, workOrderId);
      final itemSnapshot = await transaction.get(
        collection(FirestorePaths.inventoryItems).doc(inventoryItemId),
      );
      if (!itemSnapshot.exists) {
        throw FirestoreRepository.notFound(
          'This material is no longer in the inventory.',
        );
      }
      final item = InventoryItem.fromFirestore(itemSnapshot);
      if (quantity > item.quantityAvailable) {
        throw FirestoreRepository.precondition(
          'Only ${QuantityFormat.withUnit(item.quantityAvailable, item.unitOfMeasurement)} '
          'of ${item.name} in stock.',
        );
      }

      transaction.set(
        _allocated(workOrderId).doc(inventoryItemId),
        AllocatedMaterial(
          line: MaterialLine(
            inventoryItemId: inventoryItemId,
            itemName: item.name,
            quantity: quantity,
            unitOfMeasurement: item.unitOfMeasurement,
          ),
          allocatedBy: actor.id,
          allocatedAt: DateTime.now().toUtc(),
        ).toFirestore()..['allocatedAt'] = FirestoreRepository.serverNow,
      );
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.updated,
        entityType: FirestorePaths.workOrders,
        entityId: workOrderId,
        description:
            'Pre-assigned '
            '${QuantityFormat.withUnit(quantity, item.unitOfMeasurement)} of '
            '${item.name} to ${DisplayId.workOrder(workOrderId)}',
        changes: {'inventoryItemId': inventoryItemId, 'quantity': quantity},
      );
    });
  }

  @override
  Future<Result<void>> remove({
    required String workOrderId,
    required String inventoryItemId,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    await readOpenWorkOrder(transaction, db.raw, workOrderId);
    final reference = _allocated(workOrderId).doc(inventoryItemId);
    final snapshot = await transaction.get(reference);
    if (!snapshot.exists) return;
    final allocated = AllocatedMaterial.fromFirestore(snapshot);

    transaction.delete(reference);
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.updated,
      entityType: FirestorePaths.workOrders,
      entityId: workOrderId,
      description:
          'Took ${allocated.line.itemName} off '
          '${DisplayId.workOrder(workOrderId)}’s pre-assigned materials',
      changes: {'inventoryItemId': inventoryItemId},
    );
  });
}
