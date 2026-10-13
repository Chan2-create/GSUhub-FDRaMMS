import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/enums/date_range_filter.dart';
import '../../../core/enums/inventory_transaction_type.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/utils/result.dart';
import '../../inventory/data/models/inventory_item.dart';
import '../../inventory/data/models/inventory_transaction.dart';
import '../../inventory/presentation/inventory_providers.dart';
import 'analytics_export.dart';
import 'analytics_providers.dart';

/// One material's use in the period (Objective 6.C; §3.4 "identify
/// frequently consumed materials").
class MaterialUse {
  const MaterialUse({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.jobs,
    this.value,
  });

  final String itemId;
  final String name;
  final String unit;

  /// How much was used, in [unit].
  final double quantity;

  /// On how many work orders.
  final int jobs;

  /// [quantity] × the material's unit cost, when it has one.
  final double? value;
}

/// The period's movements, read for Analytics.
abstract final class InventoryUsage {
  /// Materials used in [movements], most often used first — on the most
  /// work orders, then the greater quantity. Comparing quantities alone
  /// would rank a roll against a bulb, which says nothing.
  static List<MaterialUse> mostUsed(
    List<InventoryTransaction> movements,
    Map<String, InventoryItem> items,
  ) {
    final quantities = <String, double>{};
    final jobs = <String, Set<String>>{};
    final names = <String, String>{};
    for (final movement in movements) {
      if (movement.type != InventoryTransactionType.consumption) continue;
      final id = movement.inventoryItemId;
      quantities.update(
        id,
        (total) => total + movement.quantity,
        ifAbsent: () => movement.quantity,
      );
      names[id] = movement.itemName;
      (jobs[id] ??= {}).add(movement.workOrderId ?? movement.id);
    }
    final uses = [
      for (final MapEntry(key: id, value: quantity) in quantities.entries)
        MaterialUse(
          itemId: id,
          name: items[id]?.name ?? names[id]!,
          unit: items[id]?.unitOfMeasurement ?? '',
          quantity: quantity,
          jobs: jobs[id]!.length,
          value: switch (items[id]?.unitCost) {
            final cost? => cost * quantity,
            null => null,
          },
        ),
    ];
    return uses..sort((a, b) {
      final byJobs = b.jobs.compareTo(a.jobs);
      return byJobs != 0 ? byJobs : b.quantity.compareTo(a.quantity);
    });
  }

  static final DateFormat _stamp = DateFormat('yyyy-MM-dd HH:mm');

  /// "gsuhub-inventory-last-30-days-2026-10-13.csv".
  static String fileName(DateRangeFilter range, DateTime now) =>
      'gsuhub-inventory-${range.label.toLowerCase().replaceAll(' ', '-')}-'
      '${DateFormat('yyyy-MM-dd').format(now)}.csv';

  /// The inventory report (§3.4 "generate inventory reports"): every
  /// material's stock as it stands, then every movement in [range].
  static String buildCsv({
    required List<InventoryItem> items,
    required List<InventoryTransaction> movements,
    required DateRangeFilter range,
    required DateTime now,
  }) {
    String row(List<Object?> fields) => fields
        .map((field) => AnalyticsExport.escape(field?.toString() ?? ''))
        .join(',');
    final lines = <String>[
      row(['GSUhub inventory report', range.label, _stamp.format(now)]),
      '',
      row(['STOCK']),
      row([
        'Material',
        'Category',
        'Size or pack',
        'In stock',
        'Unit',
        'Alert at or below',
        'Status',
        'Unit cost (PHP)',
        'Stock value (PHP)',
        'Stored at',
        'Code',
      ]),
      for (final item in items)
        row([
          item.name,
          item.category,
          item.specification,
          QuantityFormat.amount(item.quantityAvailable),
          item.unitOfMeasurement,
          QuantityFormat.amount(item.minimumThreshold),
          item.isOutOfStock
              ? 'Out of stock'
              : item.isLowStock
              ? 'Low stock'
              : 'In stock',
          item.unitCost?.toStringAsFixed(2),
          item.stockValue?.toStringAsFixed(2),
          item.storageLocation,
          item.qrCode,
        ]),
      '',
      row(['MOVEMENTS', range.label]),
      row([
        'When',
        'Material',
        'Movement',
        'Change',
        'Balance after',
        'Work order',
        'By',
        'Notes',
      ]),
      for (final movement in movements)
        row([
          _stamp.format(movement.performedAt.toLocal()),
          movement.itemName,
          movement.type.label,
          '${movement.change > 0 ? '+' : ''}'
              '${QuantityFormat.amount(movement.change)}',
          QuantityFormat.amount(movement.quantityAfter),
          switch (movement.workOrderId) {
            final id? => DisplayId.workOrder(id),
            null => null,
          },
          movement.performedByName ?? movement.performedBy,
          movement.notes,
        ]),
    ];
    return lines.join('\r\n');
  }
}

/// Every movement in the Analytics period, newest first.
final inventoryMovementsProvider =
    StreamProvider.autoDispose<Result<List<InventoryTransaction>>>((ref) {
      final range = ref.watch(analyticsRangeProvider);
      // A fixed moment per range change, not "now" on every rebuild.
      final since = range.startOf(DateTime.now()) ?? DateTime.utc(2000);
      return ref
          .watch(inventoryRepositoryProvider)
          .watchTransactionsSince(since);
    });

/// The period's most used materials, once movements and materials load.
final mostUsedMaterialsProvider =
    Provider.autoDispose<AsyncValue<Result<List<MaterialUse>>>>((ref) {
      final movements = ref.watch(inventoryMovementsProvider);
      final items = ref.watch(inventoryItemsProvider);
      return switch ((movements, items)) {
        (AsyncData(value: final m), AsyncData(value: final i)) => AsyncData(
          switch ((m, i)) {
            (Success(value: final moves), Success(value: final stock)) =>
              Result.success(
                InventoryUsage.mostUsed(moves, {
                  for (final item in stock) item.id: item,
                }),
              ),
            (Error(:final failure), _) ||
            (_, Error(:final failure)) => Result.failure(failure),
          },
        ),
        (AsyncError(:final error, :final stackTrace), _) ||
        (
          _,
          AsyncError(:final error, :final stackTrace),
        ) => AsyncError(error, stackTrace),
        _ => const AsyncLoading(),
      };
    });
