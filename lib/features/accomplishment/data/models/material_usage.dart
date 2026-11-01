import '../../../../core/utils/record_converters.dart';

/// One material line item inside an accomplishment report — an embedded
/// value object, not its own collection.
///
/// This is what drives automatic inventory deduction: manuscript §3.4
/// states that once the accomplishment report is submitted, "the system
/// automatically deducts the used quantity from the current inventory
/// balance and records the transaction in the inventory history log". Each
/// entry here becomes one `inventory_transactions` document of type
/// `consumption`.
class MaterialUsage {
  MaterialUsage({
    required this.inventoryItemId,
    required this.itemName,
    required this.quantityUsed,
    required this.unitOfMeasurement,
  }) {
    RecordConverters.validateNotBlank(inventoryItemId, 'inventoryItemId');
    RecordConverters.validateNotBlank(itemName, 'itemName');
    if (quantityUsed <= 0) {
      throw ArgumentError.value(
        quantityUsed,
        'quantityUsed',
        'Recorded material usage must be greater than zero',
      );
    }
  }

  factory MaterialUsage.fromMap(Map<String, dynamic> data) => MaterialUsage(
    inventoryItemId: RecordConverters.require<String>(data, 'inventoryItemId'),
    itemName: RecordConverters.require<String>(data, 'itemName'),
    quantityUsed: RecordConverters.require<num>(
      data,
      'quantityUsed',
    ).toDouble(),
    unitOfMeasurement: RecordConverters.require<String>(
      data,
      'unitOfMeasurement',
    ),
  );

  final String inventoryItemId;

  /// DENORMALIZED from `inventory_items.name` — keeps a historical
  /// accomplishment report readable even if the item is later renamed or
  /// delisted.
  final String itemName;

  /// Non-integer to support materials measured continuously (e.g. "1.5 L
  /// of coolant" — Figure 23 shows "Coolant 1 L").
  final double quantityUsed;

  /// DENORMALIZED from `inventory_items.unitOfMeasurement`, for the same
  /// historical-readability reason.
  final String unitOfMeasurement;

  Map<String, dynamic> toMap() => {
    'inventoryItemId': inventoryItemId,
    'itemName': itemName,
    'quantityUsed': quantityUsed,
    'unitOfMeasurement': unitOfMeasurement,
  };

  MaterialUsage copyWith({
    String? inventoryItemId,
    String? itemName,
    double? quantityUsed,
    String? unitOfMeasurement,
  }) => MaterialUsage(
    inventoryItemId: inventoryItemId ?? this.inventoryItemId,
    itemName: itemName ?? this.itemName,
    quantityUsed: quantityUsed ?? this.quantityUsed,
    unitOfMeasurement: unitOfMeasurement ?? this.unitOfMeasurement,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MaterialUsage &&
          other.inventoryItemId == inventoryItemId &&
          other.itemName == itemName &&
          other.quantityUsed == quantityUsed &&
          other.unitOfMeasurement == unitOfMeasurement;

  @override
  int get hashCode =>
      Object.hash(inventoryItemId, itemName, quantityUsed, unitOfMeasurement);

  @override
  String toString() =>
      'MaterialUsage(item: $itemName, quantity: $quantityUsed '
      '$unitOfMeasurement)';
}
