import '../../../../core/data/data_record.dart';
import '../../../../core/utils/record_converters.dart';
import 'material_usage.dart';

/// A material recorded as used on a work order while the work is under
/// way — `work_orders/{id}/materials_used/{inventoryItemId}` (Objective
/// 5.C).
///
/// §3.4: "During maintenance execution, the system records the quantity
/// of materials consumed for the specific work order. Once the
/// maintenance personnel submits the accomplishment report, the system
/// automatically deducts the used quantity." This is that record, between
/// the scan and the submission. One per item: recording the same item
/// again sets its quantity.
class RecordedMaterial {
  RecordedMaterial({
    required this.usage,
    required this.recordedBy,
    required this.recordedAt,
  });

  factory RecordedMaterial.fromRecord(DataRecord record) {
    final data = record.fields;
    return RecordedMaterial(
      usage: MaterialUsage.fromMap({...data, 'inventoryItemId': record.id}),
      recordedBy: RecordConverters.require<String>(data, 'recordedBy'),
      recordedAt: RecordConverters.requireDate(data, 'recordedAt'),
    );
  }

  /// The item, quantity and unit, as the accomplishment report will carry
  /// them.
  final MaterialUsage usage;

  final String recordedBy;
  final DateTime recordedAt;

  String get inventoryItemId => usage.inventoryItemId;

  Map<String, dynamic> toFields() => {
    ...usage.toMap()..remove('inventoryItemId'),
    'recordedBy': recordedBy,
    'recordedAt': recordedAt,
  };

  @override
  bool operator ==(Object other) =>
      other is RecordedMaterial &&
      other.inventoryItemId == inventoryItemId &&
      other.usage.quantityUsed == usage.quantityUsed &&
      other.usage.itemName == usage.itemName &&
      other.usage.unitOfMeasurement == usage.unitOfMeasurement &&
      other.recordedBy == recordedBy &&
      other.recordedAt == recordedAt;

  @override
  int get hashCode => Object.hash(
    inventoryItemId,
    usage.quantityUsed,
    usage.itemName,
    usage.unitOfMeasurement,
    recordedBy,
    recordedAt,
  );
}
