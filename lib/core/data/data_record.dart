/// One stored record, as a model reads it: its id and its fields.
///
/// The models know nothing of the backend that keeps them. A field's name
/// is the model's own (`reporterId`, not `reporter_id`), a time is a UTC
/// [DateTime], and a geo-tag is a `GeoCoordinates`: the backend's adapter
/// (`RowRecord` for Supabase) shapes its rows into this, so no model or
/// screen imports a database package (docs/architecture_decisions.md §3).
class DataRecord {
  const DataRecord(this.id, this.fields);

  /// The record's key.
  final String id;

  /// Its fields by name. Absent and null mean the same thing.
  final Map<String, dynamic> fields;

  @override
  String toString() => 'DataRecord($id, $fields)';
}
