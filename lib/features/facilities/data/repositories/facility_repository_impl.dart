import '../../../../core/data/row_snapshot.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/asset.dart';
import '../models/facility.dart';
import '../models/facility_draft.dart';
import 'facility_repository.dart';

/// Supabase-backed [FacilityRepository] (Objective 1).
///
/// The app checks a draft's shape before asking (FacilityDraft.problem);
/// the facility functions check what only the database can see — the code
/// is free across rooms, equipment, materials and tools, and the room
/// exists — and audit the change under the caller's own name.
class FacilityRepositoryImpl extends SupabaseRepository
    implements FacilityRepository {
  const FacilityRepositoryImpl({required super.client, required super.guard});

  static const String _facilities = 'facilities';
  static const String _assets = 'assets';

  @override
  Future<Result<Facility>> getFacilityById(String id) =>
      getOne(table: _facilities, id: id, convert: Facility.fromFirestore);

  @override
  Future<Result<Facility>> getFacilityByQrCode(String qrCode) => _byQrCode(
    table: _facilities,
    qrCode: qrCode,
    convert: Facility.fromFirestore,
    label: 'facility',
  );

  @override
  Future<Result<List<Facility>>> getFacilities({bool activeOnly = true}) {
    final query = client.from(_facilities).select();
    return getMany(
      query: activeOnly ? query.eq('is_active', true) : query,
      convert: Facility.fromFirestore,
    );
  }

  @override
  Stream<Result<List<Facility>>> watchFacilities() =>
      watchMany(
        stream: client.from(_facilities).stream(primaryKey: const ['id']),
        convert: Facility.fromFirestore,
      ).map(
        (result) => result.map(
          (facilities) => [...facilities]
            ..sort((a, b) {
              final byBuilding = a.buildingName.toLowerCase().compareTo(
                b.buildingName.toLowerCase(),
              );
              if (byBuilding != 0) return byBuilding;
              return (a.roomIdentifier ?? '').toLowerCase().compareTo(
                (b.roomIdentifier ?? '').toLowerCase(),
              );
            }),
        ),
      );

  @override
  Future<Result<String>> createFacility({
    required FacilityDraft draft,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    final clean = draft.normalized();
    final id = SupabaseRepository.newId();
    return rpcOnce<String>('create_facility', {
      'id': id,
      'building_name': clean.buildingName,
      'room_identifier': clean.roomIdentifier,
      'location_description': clean.locationDescription,
      'latitude': clean.latitude,
      'longitude': clean.longitude,
      'qr_code': clean.qrCode ?? FacilityDraft.defaultQrCode(id),
    });
  }

  @override
  Future<Result<void>> updateFacility({
    required String facilityId,
    required FacilityDraft draft,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    final clean = draft.normalized();
    return rpc('update_facility', {
      'id': facilityId,
      'building_name': clean.buildingName,
      'room_identifier': clean.roomIdentifier,
      'location_description': clean.locationDescription,
      'latitude': clean.latitude,
      'longitude': clean.longitude,
      // Null keeps the room's code.
      'qr_code': clean.qrCode,
    });
  }

  @override
  Future<Result<void>> setFacilityActive({
    required String facilityId,
    required bool active,
    required AuditActor actor,
  }) => rpc('set_facility_active', {'id': facilityId, 'active': active});

  @override
  Future<Result<Asset>> getAssetById(String id) =>
      getOne(table: _assets, id: id, convert: Asset.fromFirestore);

  @override
  Future<Result<Asset>> getAssetByQrCode(String qrCode) => _byQrCode(
    table: _assets,
    qrCode: qrCode,
    convert: Asset.fromFirestore,
    label: 'asset',
  );

  @override
  Future<Result<List<Asset>>> getAssetsForFacility(
    String facilityId, {
    bool activeOnly = true,
  }) {
    final query = client.from(_assets).select().eq('facility_id', facilityId);
    return getMany(
      query: activeOnly ? query.eq('is_active', true) : query,
      convert: Asset.fromFirestore,
    );
  }

  @override
  Stream<Result<List<Asset>>> watchAssets() =>
      watchMany(
        stream: client.from(_assets).stream(primaryKey: const ['id']),
        convert: Asset.fromFirestore,
      ).map(
        (result) => result.map(
          (assets) => [...assets]
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            ),
        ),
      );

  @override
  Future<Result<String>> createAsset({
    required AssetDraft draft,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    final clean = draft.normalized();
    final id = SupabaseRepository.newId();
    return rpcOnce<String>('create_asset', {
      'id': id,
      'name': clean.name,
      'facility_id': clean.facilityId,
      'condition': clean.condition.id,
      'category': clean.category,
      'serial_number': clean.serialNumber,
      'qr_code': clean.qrCode ?? AssetDraft.defaultQrCode(id),
    });
  }

  @override
  Future<Result<void>> updateAsset({
    required String assetId,
    required AssetDraft draft,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    final clean = draft.normalized();
    return rpc('update_asset', {
      'id': assetId,
      'name': clean.name,
      'facility_id': clean.facilityId,
      'condition': clean.condition.id,
      'category': clean.category,
      'serial_number': clean.serialNumber,
      'qr_code': clean.qrCode,
    });
  }

  @override
  Future<Result<void>> setAssetActive({
    required String assetId,
    required bool active,
    required AuditActor actor,
  }) => rpc('set_asset_active', {'id': assetId, 'active': active});

  /// QR lookup, shared by rooms and equipment. An unregistered code is
  /// [NotFoundFailure], not an error: §1.5 limits QR identification to
  /// registered items, so scanning an unknown sticker is expected.
  Future<Result<T>> _byQrCode<T>({
    required String table,
    required String qrCode,
    required T Function(RowSnapshot) convert,
    required String label,
  }) async {
    final matches = await getMany(
      query: client.from(table).select().eq('qr_code', qrCode).limit(1),
      convert: convert,
    );
    return matches.fold(
      (list) => list.isEmpty
          ? Result.failure(
              NotFoundFailure(
                'No registered $label matches that QR code. It may not be '
                'registered in GSUhub yet.',
              ),
            )
          : Result.success(list.first),
      Result.failure,
    );
  }
}
