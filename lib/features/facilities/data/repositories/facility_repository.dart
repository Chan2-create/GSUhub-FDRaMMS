import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/asset.dart';
import '../models/facility.dart';
import '../models/facility_draft.dart';

/// Abstract contract for the `facilities` and `assets` collections — the
/// registry behind QR-code identification (manuscript §1.7).
///
/// Both live here because they answer the same question ("what is this QR
/// code pointing at?") and are almost always read together.
abstract interface class FacilityRepository {
  Future<Result<Facility>> getFacilityById(String id);

  /// Resolves a scanned facility QR code. Returns a `NotFoundFailure` when
  /// the code isn't registered — §1.5 limits QR identification to
  /// facilities "registered in the system and assigned valid and readable
  /// QR codes", so an unknown code is an expected outcome, not an error to
  /// throw on.
  Future<Result<Facility>> getFacilityByQrCode(String qrCode);

  Future<Result<List<Facility>>> getFacilities({bool activeOnly = true});

  /// Every room, inactive ones included, by building then room: the
  /// console's Facilities & Equipment page (Objective 6.C).
  Stream<Result<List<Facility>>> watchFacilities();

  /// Registers a room. Its code, when [FacilityDraft.qrCode] is empty, is
  /// made from its new id. Refused when another material, tool, room or
  /// piece of equipment carries the code.
  Future<Result<String>> createFacility({
    required FacilityDraft draft,
    required AuditActor actor,
  });

  Future<Result<void>> updateFacility({
    required String facilityId,
    required FacilityDraft draft,
    required AuditActor actor,
  });

  /// Deactivates or reactivates a room. Facilities are never deleted, so
  /// old reports keep resolving; an inactive one is left out of the
  /// report form.
  Future<Result<void>> setFacilityActive({
    required String facilityId,
    required bool active,
    required AuditActor actor,
  });

  Future<Result<Asset>> getAssetById(String id);

  Future<Result<Asset>> getAssetByQrCode(String qrCode);

  /// Assets installed at a facility, for the technician arriving on site.
  Future<Result<List<Asset>>> getAssetsForFacility(
    String facilityId, {
    bool activeOnly = true,
  });

  /// Every piece of equipment, inactive included, by name.
  Stream<Result<List<Asset>>> watchAssets();

  Future<Result<String>> createAsset({
    required AssetDraft draft,
    required AuditActor actor,
  });

  Future<Result<void>> updateAsset({
    required String assetId,
    required AssetDraft draft,
    required AuditActor actor,
  });

  Future<Result<void>> setAssetActive({
    required String assetId,
    required bool active,
    required AuditActor actor,
  });
}
