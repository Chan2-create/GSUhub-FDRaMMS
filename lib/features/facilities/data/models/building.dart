import '../../../../core/data/data_record.dart';
import '../../../../core/data/geo_coordinates.dart';
import '../../../../core/utils/record_converters.dart';

/// A `buildings` row (2026-11-26): a campus building the administrator
/// registers on the Facilities page, with its pin on the map. Rooms
/// ([Facility]) belong to one and carry its name, so the report form lists
/// them under it.
class Building {
  Building({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.coordinates,
    this.deletedAt,
  }) {
    RecordConverters.validateNotBlank(name, 'name');
  }

  factory Building.fromRecord(DataRecord record) {
    final data = record.fields;
    return Building(
      id: record.id,
      name: RecordConverters.require<String>(data, 'name'),
      description: RecordConverters.optional<String>(data, 'description'),
      coordinates: RecordConverters.optional<GeoCoordinates>(
        data,
        'coordinates',
      ),
      createdAt: RecordConverters.requireDate(data, 'createdAt'),
      updatedAt: RecordConverters.requireDate(data, 'updatedAt'),
      deletedAt: RecordConverters.optionalDate(data, 'deletedAt'),
    );
  }

  final String id;

  /// "Engineering Building". One building of a name at a time.
  final String name;

  /// Wayfinding words, optional: "Beside the gymnasium".
  final String? description;

  /// The building's pin on the campus map, set by the administrator.
  /// Optional; a building without one is left off the map.
  final GeoCoordinates? coordinates;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// When an administrator deleted it. Kept for the rooms and reports
  /// that name it; left out of every list.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Building &&
          other.id == id &&
          other.name == name &&
          other.description == description &&
          other.coordinates == coordinates &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    coordinates,
    createdAt,
    updatedAt,
    deletedAt,
  );

  @override
  String toString() => 'Building(id: $id, name: $name)';
}

/// What the console's building form holds.
class BuildingDraft {
  const BuildingDraft({
    required this.name,
    this.description,
    this.latitude,
    this.longitude,
  });

  static const int nameLimit = 120;
  static const int descriptionLimit = 200;

  final String name;
  final String? description;
  final double? latitude;
  final double? longitude;

  BuildingDraft normalized() => BuildingDraft(
    name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
    description: _orNull(description),
    latitude: latitude,
    longitude: longitude,
  );

  /// Why the draft cannot be saved, or null when it can.
  String? get problem {
    final draft = normalized();
    if (draft.name.isEmpty) return 'Enter the building’s name.';
    if (draft.name.length > nameLimit) {
      return 'Keep the name to $nameLimit characters.';
    }
    if ((draft.description?.length ?? 0) > descriptionLimit) {
      return 'Keep the description to $descriptionLimit characters.';
    }
    return pinProblem(draft.latitude, draft.longitude);
  }

  /// Why a pin cannot be saved, or null when it can: both or neither, on
  /// the map.
  static String? pinProblem(double? latitude, double? longitude) {
    if ((latitude == null) != (longitude == null)) {
      return 'Enter both the latitude and the longitude, or neither.';
    }
    if (latitude != null && latitude.abs() > 90) {
      return 'The latitude must be between -90 and 90.';
    }
    if (longitude != null && longitude.abs() > 180) {
      return 'The longitude must be between -180 and 180.';
    }
    return null;
  }

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
