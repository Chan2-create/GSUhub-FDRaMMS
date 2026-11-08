import '../../../../core/data/data_record.dart';
import '../../../../core/enums/item_condition.dart';
import '../../../../core/utils/record_converters.dart';

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
    this.deletedAt,
    this.category,
    this.serialNumber,
    this.acquiredAt,
  }) {
    RecordConverters.validateNotBlank(name, 'name');
    RecordConverters.validateNotBlank(qrCode, 'qrCode');
    RecordConverters.validateNotBlank(facilityId, 'facilityId');
  }

  factory Asset.fromRecord(DataRecord record) {
    final data = record.fields;
    return Asset(
      id: record.id,
      name: RecordConverters.require<String>(data, 'name'),
      qrCode: RecordConverters.require<String>(data, 'qrCode'),
      facilityId: RecordConverters.require<String>(data, 'facilityId'),
      condition: RecordConverters.requireEnum(
        data,
        'condition',
        ItemCondition.fromId,
      ),
      isActive: RecordConverters.require<bool>(data, 'isActive'),
      category: RecordConverters.optional<String>(data, 'category'),
      serialNumber: RecordConverters.optional<String>(data, 'serialNumber'),
      acquiredAt: RecordConverters.optionalDate(data, 'acquiredAt'),
      createdAt: RecordConverters.requireDate(data, 'createdAt'),
      updatedAt: RecordConverters.requireDate(data, 'updatedAt'),
      deletedAt: RecordConverters.optionalDate(data, 'deletedAt'),
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

  /// When an administrator deleted the equipment (2026-11-08). Reports keep
  /// it in the table; it is left out of the lists, pickers and scans.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Map<String, dynamic> toFields() => {
    'name': name,
    'qrCode': qrCode,
    'facilityId': facilityId,
    'condition': condition.id,
    'category': category,
    'serialNumber': serialNumber,
    'acquiredAt': acquiredAt,
    'isActive': isActive,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
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
    DateTime? deletedAt,
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
    deletedAt: deletedAt ?? this.deletedAt,
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
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt;

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
    deletedAt,
  );

  @override
  String toString() =>
      'Asset(id: $id, name: $name, facilityId: $facilityId, '
      'condition: $condition)';
}
