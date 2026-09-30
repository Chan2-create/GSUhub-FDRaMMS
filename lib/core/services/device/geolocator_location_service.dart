import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../errors/failures.dart';
import '../../utils/result.dart';
import '../location_service.dart';

/// [LocationService] on the `geolocator` plugin — Android's fused location
/// provider, and the browser's Geolocation API on web.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService({
    this.timeLimit = const Duration(seconds: 20),
  });

  /// How long to wait for a fix. Indoors a cold GPS can take a while, but
  /// a requestor holding a form open should not wait indefinitely for a
  /// field that is optional.
  final Duration timeLimit;

  @override
  Future<Result<GeoCoordinates>> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const Result.failure(
          ValidationFailure(
            'Location is turned off on this device. Turn it on to attach '
            'where you are, or submit without it.',
          ),
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return const Result.failure(
            PermissionFailure(
              'Location access was not allowed. You can still submit '
              'without it.',
            ),
          );
        case LocationPermission.deniedForever:
          return const Result.failure(
            PermissionFailure(
              'Location access is blocked for GSUhub. Allow it in your '
              "phone's Settings to attach where you are.",
            ),
          );
        case LocationPermission.whileInUse:
        case LocationPermission.always:
        case LocationPermission.unableToDetermine:
          break;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      return Result.success(
        GeoCoordinates(
          latitude: position.latitude,
          longitude: position.longitude,
          // Zero means "not reported" on platforms that have no estimate.
          accuracyMeters: position.accuracy > 0 ? position.accuracy : null,
        ),
      );
    } on TimeoutException {
      return const Result.failure(
        NetworkFailure(
          "Couldn't get a location fix. Try again near a window or "
          'outdoors, or submit without it.',
        ),
      );
    } on PermissionDeniedException {
      return const Result.failure(
        PermissionFailure(
          'Location access was not allowed. You can still submit without '
          'it.',
        ),
      );
    } on LocationServiceDisabledException {
      return const Result.failure(
        ValidationFailure(
          'Location is turned off on this device. Turn it on to attach '
          'where you are, or submit without it.',
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnknownFailure("Couldn't read your location. ($error)"),
      );
    }
  }
}
