// DocumentSnapshot and SnapshotMetadata are marked @sealed for Firestore's
// own use. This file stands in for them on purpose; see RowSnapshot.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';

/// A Postgres row, handed to a model's `fromFirestore` as the document it
/// used to be (Objective 1).
///
/// The models were written for Firestore and are kept as they are: their
/// converters validate every field, and rewriting twenty of them for a new
/// backend would trade a working check for an untested one. So the row is
/// shaped back into the document: `snake_case` columns become the
/// `camelCase` fields, timestamps become [Timestamp]s, and `latitude` with
/// `longitude` become the `coordinates` [GeoPoint].
///
/// Only [id] and [data] are real. Nothing reads the rest, which belongs to
/// Firestore: [reference] throws, and [metadata] reports a confirmed
/// server read, which a row always is.
class RowSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  RowSnapshot(this.id, this._fields);

  /// The document a row of a table with an `id` column was.
  factory RowSnapshot.fromRow(Map<String, dynamic> row) =>
      RowSnapshot(row['id'] as String, documentFields(row));

  /// The document a row was in a subcollection keyed by another column:
  /// a work order's materials were documents named by their inventory
  /// item, and are rows keyed by (work order, item).
  factory RowSnapshot.fromKeyedRow(
    Map<String, dynamic> row, {
    required String idColumn,
  }) => RowSnapshot(row[idColumn] as String, documentFields(row));

  /// An `app_config` row: its `data` is the settings document, beside who
  /// saved it and when.
  factory RowSnapshot.fromConfigRow(Map<String, dynamic> row) =>
      RowSnapshot(row['id'] as String, {
        ...?(row['data'] as Map<String, dynamic>?),
        'updatedBy': row['updated_by'],
        'updatedAt': _timestamp(row['updated_at']),
      });

  /// The document fields of [row].
  static Map<String, dynamic> documentFields(Map<String, dynamic> row) {
    final fields = <String, dynamic>{};
    for (final MapEntry(:key, :value) in row.entries) {
      if (key == 'latitude' || key == 'longitude') continue;
      fields[_camel(key)] = _isTime(key) ? _timestamp(value) : value;
    }
    if (row.containsKey('latitude') || row.containsKey('longitude')) {
      final latitude = row['latitude'] as num?;
      final longitude = row['longitude'] as num?;
      fields['coordinates'] = latitude == null || longitude == null
          ? null
          : GeoPoint(latitude.toDouble(), longitude.toDouble());
    }
    return fields;
  }

  @override
  final String id;

  final Map<String, dynamic> _fields;

  @override
  bool get exists => true;

  @override
  Map<String, dynamic> data() => _fields;

  @override
  dynamic get(Object field) {
    if (!_fields.containsKey(field)) {
      throw StateError('field "$field" does not exist within the row');
    }
    return _fields[field];
  }

  @override
  dynamic operator [](Object field) => get(field);

  @override
  SnapshotMetadata get metadata => const _ServerRead();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('A row has no Firestore document reference.');

  /// The column a document field became: `unitOfMeasurement` is
  /// `unit_of_measurement`.
  static String columnFor(String field) {
    final column = StringBuffer();
    for (final char in field.split('')) {
      final lower = char.toLowerCase();
      column.write(char != lower ? '_$lower' : char);
    }
    return column.toString();
  }

  static bool _isTime(String column) =>
      column.endsWith('_at') ||
      column == 'timestamp' ||
      column == 'due_date' ||
      column == 'scheduled_for';

  static String _camel(String column) {
    final parts = column.split('_');
    return [
      parts.first,
      for (final part in parts.skip(1))
        if (part.isNotEmpty) part[0].toUpperCase() + part.substring(1),
    ].join();
  }

  /// A `timestamptz` as the API sends it. A time without a zone is UTC:
  /// Realtime can send one bare, and read as local it would shift by the
  /// device's offset.
  static Timestamp? _timestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return Timestamp.fromDate(value.toUtc());
    final text = value as String;
    final zoned =
        text.endsWith('Z') || RegExp(r'[+-]\d{2}(:?\d{2})?$').hasMatch(text);
    return Timestamp.fromDate(DateTime.parse(zoned ? text : '${text}Z'));
  }
}

class _ServerRead implements SnapshotMetadata {
  const _ServerRead();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => false;
}
