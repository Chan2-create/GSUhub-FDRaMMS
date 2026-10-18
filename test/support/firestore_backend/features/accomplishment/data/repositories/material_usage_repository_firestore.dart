import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/accomplishment/data/models/material_usage.dart';
import 'package:gsuhub/features/accomplishment/data/models/recorded_material.dart';
import 'package:gsuhub/features/accomplishment/data/repositories/material_usage_repository.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_item.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

import '../../../../core/data/firestore_repository.dart';

/// Firestore-backed [MaterialUsageRepository], over each work order's
/// `materials_used` subcollection.
/// Objective 1 moved this data to Supabase; the app uses [MaterialUsageRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreMaterialUsageRepository extends FirestoreRepository
    implements MaterialUsageRepository {
  const FirestoreMaterialUsageRepository({
    required super.db,
    required super.guard,
  });

  CollectionReference<Map<String, dynamic>> _recorded(String workOrderId) =>
      collection(FirestorePaths.workOrders)
          .doc(workOrderId)
          .collection(FirestorePaths.materialsUsed);

  @override
  Stream<Result<List<RecordedMaterial>>> watchForWorkOrder(
    String workOrderId,
  ) =>
      watchMany(
        query: _recorded(workOrderId),
        convert: RecordedMaterial.fromFirestore,
      ).map(
        (result) => result.map(
          (materials) => [...materials]
            ..sort(
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
  }) async {
    if (quantity <= 0) {
      return const Result.failure(
        ValidationFailure('Enter how much was used.'),
      );
    }

    return db.runTransaction<void>((transaction) async {
      final workOrderSnapshot = await transaction.get(
        collection(FirestorePaths.workOrders).doc(workOrderId),
      );
      if (!workOrderSnapshot.exists) {
        throw FirestoreRepository.notFound('No work order $workOrderId');
      }
      final workOrder = WorkOrder.fromFirestore(workOrderSnapshot);
      if (!workOrder.assignedPersonnelIds.contains(actor.id)) {
        throw FirestoreRepository.precondition(
          'This work order is not assigned to you.',
        );
      }
      if (workOrder.status != WorkOrderStatus.pending &&
          workOrder.status != WorkOrderStatus.inProgress) {
        throw FirestoreRepository.precondition(
          'This work order is ${workOrder.status.title}; materials can no '
          'longer be recorded on it.',
        );
      }

      final itemSnapshot = await transaction.get(
        collection(FirestorePaths.inventoryItems).doc(inventoryItemId),
      );
      if (!itemSnapshot.exists) {
        throw FirestoreRepository.notFound(
          'This item is no longer in the inventory.',
        );
      }
      final item = InventoryItem.fromFirestore(itemSnapshot);
      if (quantity > item.quantityAvailable) {
        throw FirestoreRepository.precondition(
          'Only ${_amount(item.quantityAvailable)} ${item.unitOfMeasurement} '
          'of ${item.name} in stock.',
        );
      }

      transaction.set(
        _recorded(workOrderId).doc(inventoryItemId),
        RecordedMaterial(
          usage: MaterialUsage(
            inventoryItemId: inventoryItemId,
            itemName: item.name,
            quantityUsed: quantity,
            unitOfMeasurement: item.unitOfMeasurement,
          ),
          recordedBy: actor.id,
          recordedAt: DateTime.now().toUtc(),
        ).toFirestore()..['recordedAt'] = FirestoreRepository.serverNow,
      );
    });
  }

  @override
  Future<Result<void>> remove({
    required String workOrderId,
    required String inventoryItemId,
  }) => guard.call(() => _recorded(workOrderId).doc(inventoryItemId).delete());

  static String _amount(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}
