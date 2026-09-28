import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../data/models/asset.dart';
import '../data/models/facility.dart';
import '../data/repositories/facility_repository.dart';

/// What a scanned QR code identified: a facility, and the asset in it when
/// the code was on a piece of equipment rather than on the room.
class QrMatch {
  const QrMatch({required this.facility, this.asset});

  final Facility facility;
  final Asset? asset;
}

/// Resolves a scanned QR code to the facility a report is about
/// (manuscript §1.7, "QR Code Identification").
///
/// Facilities and assets both carry codes (the seed prints `FAC-…` and
/// `AST-…`), so a code is tried as a facility first and then as an asset,
/// whose facility is then read. §1.5 limits QR identification to things
/// "registered in the system", so an unknown or retired code is an
/// expected answer — a [NotFoundFailure] with copy that says so — never an
/// error.
class QrLookup {
  const QrLookup(this._facilities);

  final FacilityRepository _facilities;

  static const String _unregistered =
      "This QR code isn't registered to a campus facility in GSUhub. Choose "
      'the building and room instead.';

  static const String _retired =
      'This QR code belongs to a facility that is no longer in service. '
      'Choose the building and room instead.';

  Future<Result<QrMatch>> resolve(String scanned) async {
    final code = scanned.trim();
    if (code.isEmpty) {
      return const Result.failure(NotFoundFailure(_unregistered));
    }

    final facility = await _facilities.getFacilityByQrCode(code);
    switch (facility) {
      case Success(:final value):
        return value.isActive
            ? Result.success(QrMatch(facility: value))
            : const Result.failure(NotFoundFailure(_retired));
      case Error(:final failure) when failure is! NotFoundFailure:
        return Result.failure(failure);
      case Error():
        break;
    }

    final asset = await _facilities.getAssetByQrCode(code);
    switch (asset) {
      case Success(:final value) when !value.isActive:
        return const Result.failure(NotFoundFailure(_retired));
      case Success(:final value):
        final home = await _facilities.getFacilityById(value.facilityId);
        return switch (home) {
          Success(value: final place) when place.isActive => Result.success(
            QrMatch(facility: place, asset: value),
          ),
          Success() => const Result.failure(NotFoundFailure(_retired)),
          Error(:final failure) when failure is NotFoundFailure =>
            const Result.failure(NotFoundFailure(_unregistered)),
          Error(:final failure) => Result.failure(failure),
        };
      case Error(:final failure) when failure is NotFoundFailure:
        return const Result.failure(NotFoundFailure(_unregistered));
      case Error(:final failure):
        return Result.failure(failure);
    }
  }
}

final qrLookupProvider = Provider<QrLookup>(
  (ref) => QrLookup(ref.watch(facilityRepositoryProvider)),
);
