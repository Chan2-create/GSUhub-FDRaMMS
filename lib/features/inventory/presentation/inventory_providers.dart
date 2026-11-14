import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/utils/result.dart';
import '../data/models/allocated_material.dart';
import '../data/models/inventory_item.dart';
import '../data/models/inventory_transaction.dart';
import '../data/models/material_request.dart';

/// What the console's Inventory Management page reads for materials and
/// requests (Objective 6), all live. The tools' providers are in
/// `features/tools/presentation/tool_providers.dart`.

/// Every material, by name.
final inventoryItemsProvider =
    StreamProvider.autoDispose<Result<List<InventoryItem>>>(
      (ref) => ref.watch(inventoryRepositoryProvider).watchItems(),
    );

/// One material, for its details dialog.
final inventoryItemProvider = StreamProvider.autoDispose
    .family<Result<InventoryItem>, String>(
      (ref, id) => ref.watch(inventoryRepositoryProvider).watchItem(id),
    );

/// A material's ledger, newest first: its stock history (§3.4).
final itemHistoryProvider = StreamProvider.autoDispose
    .family<Result<List<InventoryTransaction>>, String>(
      (ref, id) =>
          ref.watch(inventoryRepositoryProvider).watchTransactionsForItem(id),
    );

/// How many materials are at or below their minimum: the low-stock alert
/// the sidebar and the stat card show (§1.5). Zero until the list loads.
final lowStockCountProvider = Provider.autoDispose<int>(
  (ref) => switch (ref.watch(inventoryItemsProvider)) {
    AsyncData(value: Success(:final value)) =>
      value.where((item) => item.isLowStock).length,
    _ => 0,
  },
);

/// The newest material requests across all work orders.
final recentMaterialRequestsProvider =
    StreamProvider.autoDispose<Result<List<MaterialRequest>>>(
      (ref) => ref.watch(materialRequestRepositoryProvider).watchRecent(),
    );

/// A work order's requests, for the console's work-order page.
final workOrderMaterialRequestsProvider = StreamProvider.autoDispose
    .family<Result<List<MaterialRequest>>, String>(
      (ref, workOrderId) => ref
          .watch(materialRequestRepositoryProvider)
          .watchForWorkOrder(workOrderId),
    );

/// What GSU has pre-assigned to a work order (Group 43).
final allocatedMaterialsProvider = StreamProvider.autoDispose
    .family<Result<List<AllocatedMaterial>>, String>(
      (ref, workOrderId) => ref
          .watch(materialAllocationRepositoryProvider)
          .watchForWorkOrder(workOrderId),
    );
