import '../../../../core/utils/record_converters.dart';

/// A material and a quantity: one line of a technician's request, or one
/// material pre-assigned to a work order (Objective 6.B).
///
/// The name and unit are copied from the item, as a ledger entry's are,
/// so a request still reads as it was made after the item is renamed.
class MaterialLine {
  MaterialLine({
    required this.inventoryItemId,
    required this.itemName,
    required this.quantity,
    required this.unitOfMeasurement,
  }) {
    RecordConverters.validateNotBlank(inventoryItemId, 'inventoryItemId');
    RecordConverters.validateNotBlank(itemName, 'itemName');
    if (quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'A material quantity must be greater than zero',
      );
    }
  }

  factory MaterialLine.fromMap(Map<String, dynamic> data) => MaterialLine(
    inventoryItemId: RecordConverters.require<String>(data, 'inventoryItemId'),
    itemName: RecordConverters.require<String>(data, 'itemName'),
    quantity: RecordConverters.require<num>(data, 'quantity').toDouble(),
    unitOfMeasurement: RecordConverters.require<String>(
      data,
      'unitOfMeasurement',
    ),
  );

  final String inventoryItemId;
  final String itemName;

  /// Non-integer, as stock is: litres, metres.
  final double quantity;

  final String unitOfMeasurement;

  Map<String, dynamic> toMap() => {
    'inventoryItemId': inventoryItemId,
    'itemName': itemName,
    'quantity': quantity,
    'unitOfMeasurement': unitOfMeasurement,
  };

  MaterialLine withQuantity(double quantity) => MaterialLine(
    inventoryItemId: inventoryItemId,
    itemName: itemName,
    quantity: quantity,
    unitOfMeasurement: unitOfMeasurement,
  );

  @override
  bool operator ==(Object other) =>
      other is MaterialLine &&
      other.inventoryItemId == inventoryItemId &&
      other.itemName == itemName &&
      other.quantity == quantity &&
      other.unitOfMeasurement == unitOfMeasurement;

  @override
  int get hashCode =>
      Object.hash(inventoryItemId, itemName, quantity, unitOfMeasurement);

  @override
  String toString() => 'MaterialLine($itemName × $quantity $unitOfMeasurement)';
}
