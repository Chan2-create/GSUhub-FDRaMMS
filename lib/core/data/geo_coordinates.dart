/// A point on the earth: a device's reading, or a stored geo-tag.
///
/// A plain value, so the screens that capture a location and the models
/// that keep one never import a database package. A stored geo-tag has no
/// [accuracyMeters]: only the device's reading does.
class GeoCoordinates {
  const GeoCoordinates({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;

  /// Radius of the fix's 68% confidence circle, when the platform reports
  /// one. Worth showing: manuscript §2.2 notes GPS is imprecise inside
  /// multi-storey buildings, which is where most damage is reported from.
  final double? accuracyMeters;

  @override
  bool operator ==(Object other) =>
      other is GeoCoordinates &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracyMeters == accuracyMeters;

  @override
  int get hashCode => Object.hash(latitude, longitude, accuracyMeters);

  @override
  String toString() => 'GeoCoordinates($latitude, $longitude)';
}
