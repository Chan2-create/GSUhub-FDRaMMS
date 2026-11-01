import '../data/geo_coordinates.dart';
import '../utils/result.dart';

export '../data/geo_coordinates.dart';

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
