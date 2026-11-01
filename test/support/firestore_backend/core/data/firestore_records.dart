import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/data/data_record.dart';
import 'package:gsuhub/core/data/geo_coordinates.dart';

/// The record a Firestore document holds, as the models read it: a
/// [Timestamp] becomes a UTC [DateTime] and a [GeoPoint] a
/// [GeoCoordinates], at any depth.
///
/// The models are backend-neutral since Objective 7.A; this harness, the
/// Firestore backend the app used before Objective 1, adapts to them.
DataRecord firestoreRecord(DocumentSnapshot<Map<String, dynamic>> doc) =>
    DataRecord(doc.id, _plainMap(doc.data() ?? const <String, dynamic>{}));

/// [convert] reading a Firestore document: `fromDoc(Tool.fromRecord)` is
/// what `Tool.fromFirestore` was.
T Function(DocumentSnapshot<Map<String, dynamic>>) fromDoc<T>(
  T Function(DataRecord) convert,
) =>
    (doc) => convert(firestoreRecord(doc));

/// A model's fields as Firestore stores them.
extension FirestoreData on Map<String, dynamic> {
  /// [DateTime]s as [Timestamp]s and [GeoCoordinates] as [GeoPoint]s, at
  /// any depth. Anything else, a `FieldValue` sentinel included, as it is.
  Map<String, dynamic> get forFirestore => {
    for (final MapEntry(:key, :value) in entries) key: _firestore(value),
  };
}

Map<String, dynamic> _plainMap(Map<String, dynamic> data) => {
  for (final MapEntry(:key, :value) in data.entries) key: _plain(value),
};

Object? _plain(Object? value) => switch (value) {
  Timestamp() => value.toDate().toUtc(),
  GeoPoint() => GeoCoordinates(
    latitude: value.latitude,
    longitude: value.longitude,
  ),
  Map<String, dynamic>() => _plainMap(value),
  List<dynamic>() => [for (final element in value) _plain(element)],
  _ => value,
};

Object? _firestore(Object? value) => switch (value) {
  DateTime() => Timestamp.fromDate(value),
  GeoCoordinates() => GeoPoint(value.latitude, value.longitude),
  Map<String, dynamic>() => value.forFirestore,
  List<dynamic>() => [for (final element in value) _firestore(element)],
  _ => value,
};
