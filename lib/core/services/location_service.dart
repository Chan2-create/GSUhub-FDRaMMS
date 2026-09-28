import '../utils/result.dart';

/// A point on the earth, as the device measured it.
///
/// A plain value rather than Firestore's `GeoPoint`, so the screens that
/// capture a location never import Firebase. The report repository
/// converts it on the way in.
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

/// Device location — the geo-tag on a damage report (manuscript §1.5).
///
/// Geo-tagging is supplementary: §2.2 is explicit that it "does not replace
/// the requestor's own location details". So every failure here is one the
/// form can shrug off, and each carries copy that says what to do next
/// rather than why the platform refused.
abstract interface class LocationService {
  /// One reading of the device's current position, asking for permission
  /// first if it has not been decided.
  ///
  /// Fails with a `PermissionFailure` when the user declines (or has
  /// blocked the app in Settings), and a `ValidationFailure` when location
  /// is switched off on the device.
  Future<Result<GeoCoordinates>> currentPosition();
}
