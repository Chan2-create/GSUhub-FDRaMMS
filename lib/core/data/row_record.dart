import 'data_record.dart';
import 'geo_coordinates.dart';

/// A Postgres row, shaped into the [DataRecord] the models read
/// (Objective 1; backend-neutral since Objective 7.A).
///
/// The models keep their field names and their converters, which validate
/// every field: `snake_case` columns become the `camelCase` fields,
/// timestamps become UTC [DateTime]s, and `latitude` with `longitude`
/// become the `coordinates` [GeoCoordinates].
abstract final class RowRecord {
  /// The record of a row of a table with an `id` column.
  static DataRecord fromRow(Map<String, dynamic> row) =>
      DataRecord(row['id'] as String, fields(row));

  /// The record of a row keyed by another column: a work order's materials
  /// are rows keyed by (work order, item), each named by its item.
  static DataRecord fromKeyedRow(
    Map<String, dynamic> row, {
    required String idColumn,
  }) => DataRecord(row[idColumn] as String, fields(row));

  /// An `app_config` row: its `data` is the settings, beside who saved
  /// them and when.
  static DataRecord fromConfigRow(Map<String, dynamic> row) =>
      DataRecord(row['id'] as String, {
        ...?(row['data'] as Map<String, dynamic>?),
        'updatedBy': row['updated_by'],
        'updatedAt': _time(row['updated_at']),
      });

  /// The model fields of [row].
  static Map<String, dynamic> fields(Map<String, dynamic> row) {
    final fields = <String, dynamic>{};
    for (final MapEntry(:key, :value) in row.entries) {
      if (key == 'latitude' || key == 'longitude') continue;
      fields[_camel(key)] = _isTime(key) ? _time(value) : value;
    }
    if (row.containsKey('latitude') || row.containsKey('longitude')) {
      final latitude = row['latitude'] as num?;
      final longitude = row['longitude'] as num?;
      fields['coordinates'] = latitude == null || longitude == null
          ? null
          : GeoCoordinates(
              latitude: latitude.toDouble(),
              longitude: longitude.toDouble(),
            );
    }
    return fields;
  }

  /// The column a model field became: `unitOfMeasurement` is
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

  /// A `timestamptz` as the API sends it, as a UTC [DateTime]. A time
  /// without a zone is UTC: Realtime can send one bare, and read as local
  /// it would shift by the device's offset.
  static DateTime? _time(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    final text = value as String;
    final zoned =
        text.endsWith('Z') || RegExp(r'[+-]\d{2}(:?\d{2})?$').hasMatch(text);
    return DateTime.parse(zoned ? text : '${text}Z').toUtc();
  }
}
