import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/utils/firestore_converters.dart';

/// A `facilities` document — a registered campus building, room, or area
/// that can be QR-identified and reported against (manuscript §1.7 "QR
/// Code Identification": unique QR codes assigned to campus facilities;
/// §1.5 limits QR identification to facilities "registered in the system
/// and assigned valid and readable QR codes").
///
/// Most fields here are DERIVED: the manuscript establishes that
/// facilities are registered and QR-tagged, and the report form shows a
/// BUILDING / ROOM pair (Figure 21), but never gives a field list. See
/// docs/data_dictionary.md.
class Facility {
  Facility({
    required this.id,
    required this.name,
    required this.buildingName,
    required this.qrCode,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.roomIdentifier,
    this.locationDescription,
    this.coordinates,
  }) {
    FirestoreConverters.validateNotBlank(name, 'name');
    FirestoreConverters.validateNotBlank(buildingName, 'buildingName');
    FirestoreConverters.validateNotBlank(qrCode, 'qrCode');
  }

  factory Facility.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Facility(
      id: doc.id,
      name: FirestoreConverters.require<String>(data, 'name'),
      buildingName: FirestoreConverters.require<String>(data, 'buildingName'),
      qrCode: FirestoreConverters.require<String>(data, 'qrCode'),
      isActive: FirestoreConverters.require<bool>(data, 'isActive'),
      roomIdentifier: FirestoreConverters.optional<String>(
        data,
        'roomIdentifier',
      ),
      locationDescription: FirestoreConverters.optional<String>(
        data,
        'locationDescription',
      ),
      coordinates: FirestoreConverters.optional<GeoPoint>(data, 'coordinates'),
      createdAt: FirestoreConverters.requireDate(data, 'createdAt'),
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
    );
  }

  final String id;

  /// Display name, e.g. "Engineering Building" (Figure 21).
  final String name;

  final String buildingName;

  /// Room or sub-area, e.g. "Room 101" (Figure 21). Null for
  /// whole-building or outdoor facilities.
  final String? roomIdentifier;

  /// Free-text wayfinding detail, e.g. "3rd Floor, West Wing".
  final String? locationDescription;

  /// Reference coordinates for the facility itself, distinct from the
  /// geo-tag captured on an individual report. Optional because indoor
  /// facilities in multi-storey buildings gain little from a single point
  /// (manuscript §2.2 notes GPS accuracy limits in such buildings).
  final GeoPoint? coordinates;

  /// Value encoded in this facility's printed QR code. Unique across
  /// `facilities`; enforced by application logic and rules, since
  /// Firestore has no unique-field constraint.
  final String qrCode;

  /// Soft-delete flag — facilities are deactivated rather than removed so
  /// historical reports keep resolving their [facilityName] denormalized
  /// copy against a real document.
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'buildingName': buildingName,
    'roomIdentifier': roomIdentifier,
    'locationDescription': locationDescription,
    'coordinates': coordinates,
    'qrCode': qrCode,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Facility copyWith({
    String? id,
    String? name,
    String? buildingName,
    String? roomIdentifier,
    String? locationDescription,
    GeoPoint? coordinates,
    String? qrCode,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Facility(
    id: id ?? this.id,
    name: name ?? this.name,
    buildingName: buildingName ?? this.buildingName,
    roomIdentifier: roomIdentifier ?? this.roomIdentifier,
    locationDescription: locationDescription ?? this.locationDescription,
    coordinates: coordinates ?? this.coordinates,
    qrCode: qrCode ?? this.qrCode,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Facility &&
          other.id == id &&
          other.name == name &&
          other.buildingName == buildingName &&
          other.roomIdentifier == roomIdentifier &&
          other.locationDescription == locationDescription &&
          other.coordinates == coordinates &&
          other.qrCode == qrCode &&
          other.isActive == isActive &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    buildingName,
    roomIdentifier,
    locationDescription,
    coordinates,
    qrCode,
    isActive,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'Facility(id: $id, name: $name, building: $buildingName, '
      'room: $roomIdentifier, qrCode: $qrCode)';
}
