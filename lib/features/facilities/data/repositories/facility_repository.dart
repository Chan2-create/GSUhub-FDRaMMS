import '../../../../core/utils/result.dart';
import '../models/asset.dart';
import '../models/facility.dart';

/// Abstract contract for the `facilities` and `assets` collections — the
/// registry behind QR-code identification (manuscript §1.7).
///
/// Both live here because they answer the same question ("what is this QR
/// code pointing at?") and are almost always read together.
///
/// **Interface only** — implementation is 1.C.
abstract interface class FacilityRepository {
  Future<Result<Facility>> getFacilityById(String id);

  /// Resolves a scanned facility QR code. Returns a `NotFoundFailure` when
  /// the code isn't registered — §1.5 limits QR identification to
  /// facilities "registered in the system and assigned valid and readable
  /// QR codes", so an unknown code is an expected outcome, not an error to
  /// throw on.
  Future<Result<Facility>> getFacilityByQrCode(String qrCode);

  Future<Result<List<Facility>>> getFacilities({bool activeOnly = true});

  Future<Result<String>> createFacility(Facility facility);

  Future<Result<void>> updateFacility(Facility facility);

  /// Soft-delete. Facilities are deactivated rather than removed so
  /// historical reports keep resolving against a real document.
  Future<Result<void>> deactivateFacility(String id);

  Future<Result<Asset>> getAssetById(String id);

  Future<Result<Asset>> getAssetByQrCode(String qrCode);

  /// Assets installed at a facility, for the technician arriving on site.
  Future<Result<List<Asset>>> getAssetsForFacility(
    String facilityId, {
    bool activeOnly = true,
  });

  Future<Result<String>> createAsset(Asset asset);

  Future<Result<void>> updateAsset(Asset asset);

  Future<Result<void>> deactivateAsset(String id);
}
