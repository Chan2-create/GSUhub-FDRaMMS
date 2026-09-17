import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../models/asset.dart';
import '../models/facility.dart';
import 'facility_repository.dart';

/// Firestore-backed [FacilityRepository]. Persistence only.
class FacilityRepositoryImpl extends FirestoreRepository
    implements FacilityRepository {
  const FacilityRepositoryImpl({required super.db, required super.guard});

  static const String _facilities = FirestorePaths.facilities;
  static const String _assets = FirestorePaths.assets;

  @override
  Future<Result<Facility>> getFacilityById(String id) =>
      getOne(path: _facilities, id: id, convert: Facility.fromFirestore);

  @override
  Future<Result<Facility>> getFacilityByQrCode(String qrCode) => _firstByQrCode(
    path: _facilities,
    qrCode: qrCode,
    convert: Facility.fromFirestore,
    label: 'facility',
  );

  @override
  Future<Result<List<Facility>>> getFacilities({bool activeOnly = true}) {
    Query<Map<String, dynamic>> query = collection(_facilities);
    if (activeOnly) {
      query = query.where('isActive', isEqualTo: true);
    }
    return getMany(query: query, convert: Facility.fromFirestore);
  }

  @override
  Future<Result<String>> createFacility(Facility facility) =>
      add(path: _facilities, data: facility.toFirestore());

  @override
  Future<Result<void>> updateFacility(Facility facility) => updateDoc(
    path: _facilities,
    id: facility.id,
    data: {
      ...facility.toFirestore(),
      'updatedAt': FirestoreRepository.serverNow,
    },
  );

  @override
  Future<Result<void>> deactivateFacility(String id) => updateDoc(
    path: _facilities,
    id: id,
    data: {'isActive': false, 'updatedAt': FirestoreRepository.serverNow},
  );

  @override
  Future<Result<Asset>> getAssetById(String id) =>
      getOne(path: _assets, id: id, convert: Asset.fromFirestore);

  @override
  Future<Result<Asset>> getAssetByQrCode(String qrCode) => _firstByQrCode(
    path: _assets,
    qrCode: qrCode,
    convert: Asset.fromFirestore,
    label: 'asset',
  );

  @override
  Future<Result<List<Asset>>> getAssetsForFacility(
    String facilityId, {
    bool activeOnly = true,
  }) {
    Query<Map<String, dynamic>> query = collection(_assets)
        .where('facilityId', isEqualTo: facilityId);
    if (activeOnly) {
      query = query.where('isActive', isEqualTo: true);
    }
    return getMany(query: query, convert: Asset.fromFirestore);
  }

  @override
  Future<Result<String>> createAsset(Asset asset) =>
      add(path: _assets, data: asset.toFirestore());

  @override
  Future<Result<void>> updateAsset(Asset asset) => updateDoc(
    path: _assets,
    id: asset.id,
    data: {...asset.toFirestore(), 'updatedAt': FirestoreRepository.serverNow},
  );

  @override
  Future<Result<void>> deactivateAsset(String id) => updateDoc(
    path: _assets,
    id: id,
    data: {'isActive': false, 'updatedAt': FirestoreRepository.serverNow},
  );

  /// QR lookup, shared by facilities and assets.
  ///
  /// Returns [NotFoundFailure] for an unregistered code rather than
  /// throwing: manuscript §1.5 limits QR identification to registered
  /// items, so scanning an unknown sticker is an expected outcome the UI
  /// must handle gracefully, not an exceptional one.
  Future<Result<T>> _firstByQrCode<T>({
    required String path,
    required String qrCode,
    required T Function(DocumentSnapshot<Map<String, dynamic>>) convert,
    required String label,
  }) async {
    final matches = await getMany(
      query: collection(path).where('qrCode', isEqualTo: qrCode).limit(1),
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
