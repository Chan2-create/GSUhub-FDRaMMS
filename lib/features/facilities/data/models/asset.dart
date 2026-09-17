import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/enums/item_condition.dart';
import '../../../../core/utils/firestore_converters.dart';

/// An `assets` document — a registered piece of equipment installed at a
/// facility (an air-conditioning unit, a light fixture) that can be
/// QR-identified during reporting and maintenance (manuscript §1.7 "QR
/// Code Identification": QR codes assigned to "campus facilities and
/// equipment"; §1.5 "QR code-based identification of registered facilities
/// and assets").
///
/// Distinct from [Facility] (the place) and from `tools` (portable
/// equipment personnel borrow). An asset is fixed to a location and is
/// something reports are filed *about*.
///
/// Field list is largely DERIVED — see docs/data_dictionary.md.
class Asset {
  Asset({
    required this.id,
    required this.name,
    required this.qrCode,
    required this.facilityId,
    required this.condition,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.serialNumber,
    this.acquiredAt,
  }) {
    FirestoreConverters.validateNotBlank(name, 'name');
    FirestoreConverters.validateNotBlank(qrCode, 'qrCode');
    FirestoreConverters.validateNotBlank(facilityId, 'facilityId');
  }

  factory Asset.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Asset(
      id: doc.id,
      name: FirestoreConverters.require<String>(data, 'name'),
      qrCode: FirestoreConverters.require<String>(data, 'qrCode'),
      facilityId: FirestoreConverters.require<String>(data, 'facilityId'),
      condition: FirestoreConverters.requireEnum(
        data,
        'condition',
        ItemCondition.fromId,
      ),
      isActive: FirestoreConverters.require<bool>(data, 'isActive'),
      category: FirestoreConverters.optional<String>(data, 'category'),
      serialNumber: FirestoreConverters.optional<String>(data, 'serialNumber'),
      acquiredAt: FirestoreConverters.optionalDate(data, 'acquiredAt'),
      createdAt: FirestoreConverters.requireDate(data, 'createdAt'),
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
    );
  }

  final String id;
  final String name;

  /// Value encoded in this asset's printed QR code. Unique across
  /// `assets`.
  final String qrCode;

  /// The [Facility] this asset is installed in. Required — an asset with
  /// no location can't be found by a technician.
  final String facilityId;

  final ItemCondition condition;

  /// Free-text classification (e.g. "Air Conditioning Unit"). Left as a
  /// string rather than an enum: the manuscript never enumerates asset
  /// types, and inventing a closed set would force a schema change the
  /// first time GSU registers something unanticipated.
  final String? category;

  final String? serialNumber;
  final DateTime? acquiredAt;

  /// Soft-delete flag, for the same reason as [Facility.isActive].
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'qrCode': qrCode,
    'facilityId': facilityId,
    'condition': condition.id,
    'category': category,
    'serialNumber': serialNumber,
    'acquiredAt': acquiredAt == null ? null : Timestamp.fromDate(acquiredAt!),
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Asset copyWith({
    String? id,
    String? name,
    String? qrCode,
    String? facilityId,
    ItemCondition? condition,
    String? category,
    String? serialNumber,
    DateTime? acquiredAt,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Asset(
    id: id ?? this.id,
    name: name ?? this.name,
    qrCode: qrCode ?? this.qrCode,
    facilityId: facilityId ?? this.facilityId,
    condition: condition ?? this.condition,
    category: category ?? this.category,
    serialNumber: serialNumber ?? this.serialNumber,
    acquiredAt: acquiredAt ?? this.acquiredAt,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Asset &&
          other.id == id &&
          other.name == name &&
          other.qrCode == qrCode &&
          other.facilityId == facilityId &&
          other.condition == condition &&
          other.category == category &&
          other.serialNumber == serialNumber &&
          other.acquiredAt == acquiredAt &&
          other.isActive == isActive &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    qrCode,
    facilityId,
    condition,
    category,
    serialNumber,
    acquiredAt,
    isActive,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'Asset(id: $id, name: $name, facilityId: $facilityId, '
      'condition: $condition)';
}
