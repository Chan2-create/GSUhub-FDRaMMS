import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/enums/item_condition.dart';
import '../../../../core/utils/firestore_converters.dart';

/// An `inventory_items` document — a consumable maintenance material or
/// replacement part.
///
/// This is one of the few entities the manuscript specifies field by
/// field. §3.4, "Inventory and Material Consumption Tracking": *"Each
/// inventory item contains the following information: Item name,
/// Category, Quantity available, Unit of measurement, Assigned storage
/// location, QR code or barcode identifier, Status and condition."*
/// [minimumThreshold] is the eighth field, implied by §1.5's "automatic
/// low-stock alerts when recorded inventory quantities reach their
/// predefined minimum thresholds".
///
/// Consumables live here; durable equipment personnel borrow and return
/// lives in `tools`. Different lifecycles — a consumable is deducted, a
/// tool is checked out and checked back in.
///
/// **[quantityAvailable] must never be written without a matching
/// `inventory_transactions` record.** This model cannot enforce that on
/// its own; the repository contract and security rules carry that
/// obligation. See docs/data_dictionary.md.
class InventoryItem {
  InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantityAvailable,
    required this.unitOfMeasurement,
    required this.storageLocation,
    required this.qrCode,
    required this.minimumThreshold,
    required this.createdAt,
    required this.updatedAt,
    this.condition,
  }) {
    FirestoreConverters.validateNotBlank(name, 'name');
    FirestoreConverters.validateNotBlank(category, 'category');
    FirestoreConverters.validateNotBlank(
      unitOfMeasurement,
      'unitOfMeasurement',
    );
    FirestoreConverters.validateNotBlank(qrCode, 'qrCode');
    FirestoreConverters.validateNonNegative(
      quantityAvailable,
      'quantityAvailable',
    );
    FirestoreConverters.validateNonNegative(
      minimumThreshold,
      'minimumThreshold',
    );
  }

  factory InventoryItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return InventoryItem(
      id: doc.id,
      name: FirestoreConverters.require<String>(data, 'name'),
      category: FirestoreConverters.require<String>(data, 'category'),
      quantityAvailable: FirestoreConverters.require<num>(
        data,
        'quantityAvailable',
      ).toDouble(),
      unitOfMeasurement: FirestoreConverters.require<String>(
        data,
        'unitOfMeasurement',
      ),
      storageLocation: FirestoreConverters.require<String>(
        data,
        'storageLocation',
      ),
      qrCode: FirestoreConverters.require<String>(data, 'qrCode'),
      minimumThreshold: FirestoreConverters.require<num>(
        data,
        'minimumThreshold',
      ).toDouble(),
      condition: FirestoreConverters.optionalEnum(
        data,
        'condition',
        ItemCondition.fromId,
      ),
      createdAt: FirestoreConverters.requireDate(data, 'createdAt'),
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
    );
  }

  final String id;
  final String name;

  /// Free-text grouping such as "Electrical" or "Plumbing" (Figure 15
  /// shows items labelled this way). Left as a string rather than reusing
  /// `DamageCategory`: stock categories and damage categories overlap but
  /// are not the same taxonomy — "Paint · 5 Gal" has no damage-category
  /// equivalent.
  final String category;

  /// Current balance. Non-integer to support continuously measured
  /// materials (litres, metres).
  final double quantityAvailable;

  final String unitOfMeasurement;
  final String storageLocation;

  /// QR or barcode value used when scanning materials during work-order
  /// execution (§1.5).
  final String qrCode;

  /// Balance at or below which a low-stock alert fires (§1.5).
  final double minimumThreshold;

  /// Optional for consumables — the manuscript lists "status and
  /// condition" for inventory items, but condition is only meaningful for
  /// stock that can degrade in storage.
  final ItemCondition? condition;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether a low-stock alert should be raised (§1.5).
  bool get isLowStock => quantityAvailable <= minimumThreshold;

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'category': category,
    'quantityAvailable': quantityAvailable,
    'unitOfMeasurement': unitOfMeasurement,
    'storageLocation': storageLocation,
    'qrCode': qrCode,
    'minimumThreshold': minimumThreshold,
    'condition': condition?.id,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  InventoryItem copyWith({
    String? id,
    String? name,
    String? category,
    double? quantityAvailable,
    String? unitOfMeasurement,
    String? storageLocation,
    String? qrCode,
    double? minimumThreshold,
    ItemCondition? condition,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => InventoryItem(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    quantityAvailable: quantityAvailable ?? this.quantityAvailable,
    unitOfMeasurement: unitOfMeasurement ?? this.unitOfMeasurement,
    storageLocation: storageLocation ?? this.storageLocation,
    qrCode: qrCode ?? this.qrCode,
    minimumThreshold: minimumThreshold ?? this.minimumThreshold,
    condition: condition ?? this.condition,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItem &&
          other.id == id &&
          other.name == name &&
          other.category == category &&
          other.quantityAvailable == quantityAvailable &&
          other.unitOfMeasurement == unitOfMeasurement &&
          other.storageLocation == storageLocation &&
          other.qrCode == qrCode &&
          other.minimumThreshold == minimumThreshold &&
          other.condition == condition &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    category,
    quantityAvailable,
    unitOfMeasurement,
    storageLocation,
    qrCode,
    minimumThreshold,
    condition,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'InventoryItem(id: $id, name: $name, quantity: $quantityAvailable '
      '$unitOfMeasurement, lowStock: $isLowStock)';
}
