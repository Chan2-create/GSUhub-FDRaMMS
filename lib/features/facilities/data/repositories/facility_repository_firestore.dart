import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/data/qr_codes.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../models/asset.dart';
import '../models/facility.dart';
import '../models/facility_draft.dart';
import 'facility_repository.dart';

/// Firestore-backed [FacilityRepository].
/// Objective 1 moved this data to Supabase; the app uses [FacilityRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreFacilityRepository extends FirestoreRepository
    implements FacilityRepository {
  const FirestoreFacilityRepository({required super.db, required super.guard});

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
  Stream<Result<List<Facility>>> watchFacilities() =>
      watchMany(
        query: collection(_facilities),
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
    final reference = collection(_facilities).doc();
    final code = clean.qrCode ?? FacilityDraft.defaultQrCode(reference.id);
    if (await _codeTaken(code) case final failure?) {
      return Result.failure(failure);
    }

    return db.runTransaction<String>((transaction) async {
      transaction.set(reference, {
        ..._facilityFields(clean, code),
        'isActive': true,
        'createdAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      });
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.created,
        entityType: _facilities,
        entityId: reference.id,
        description: 'Added ${_placeName(clean)}',
      );
      return reference.id;
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
    if (clean.qrCode case final code?) {
      if (await _codeTaken(code, exceptId: facilityId) case final failure?) {
        return Result.failure(failure);
      }
    }

    return db.runTransaction<void>((transaction) async {
      final reference = collection(_facilities).doc(facilityId);
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw FirestoreRepository.notFound('No room $facilityId');
      }
      final before = snapshot.data() ?? const <String, dynamic>{};
      final code = clean.qrCode ?? before['qrCode'] as String;
      final fields = _facilityFields(clean, code);
      final changes = _changes(before, fields);
      if (changes.isEmpty) return;

      transaction.update(reference, {
        ...fields,
        'updatedAt': FirestoreRepository.serverNow,
      });
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.updated,
        entityType: _facilities,
        entityId: facilityId,
        description: 'Updated ${_placeName(clean)}',
        changes: changes,
      );
    });
  }

  @override
  Future<Result<void>> setFacilityActive({
    required String facilityId,
    required bool active,
    required AuditActor actor,
  }) => _setActive(
    path: _facilities,
    id: facilityId,
    active: active,
    actor: actor,
    nameOf: (data) =>
        [data['buildingName'], ?data['roomIdentifier']].join(', '),
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
  Stream<Result<List<Asset>>> watchAssets() =>
      watchMany(query: collection(_assets), convert: Asset.fromFirestore).map(
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
    final reference = collection(_assets).doc();
    final code = clean.qrCode ?? AssetDraft.defaultQrCode(reference.id);
    if (await _codeTaken(code) case final failure?) {
      return Result.failure(failure);
    }

    return db.runTransaction<String>((transaction) async {
      await _requireFacility(transaction, clean.facilityId);
      transaction.set(reference, {
        ..._assetFields(clean, code),
        'acquiredAt': null,
        'isActive': true,
        'createdAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      });
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.created,
        entityType: _assets,
        entityId: reference.id,
        description: 'Added ${clean.name}',
      );
      return reference.id;
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
    if (clean.qrCode case final code?) {
      if (await _codeTaken(code, exceptId: assetId) case final failure?) {
        return Result.failure(failure);
      }
    }

    return db.runTransaction<void>((transaction) async {
      final reference = collection(_assets).doc(assetId);
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw FirestoreRepository.notFound('No equipment $assetId');
      }
      await _requireFacility(transaction, clean.facilityId);
      final before = snapshot.data() ?? const <String, dynamic>{};
      final code = clean.qrCode ?? before['qrCode'] as String;
      final fields = _assetFields(clean, code);
      final changes = _changes(before, fields);
      if (changes.isEmpty) return;

      transaction.update(reference, {
        ...fields,
        'updatedAt': FirestoreRepository.serverNow,
      });
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.updated,
        entityType: _assets,
        entityId: assetId,
        description: 'Updated ${clean.name}',
        changes: changes,
      );
    });
  }

  @override
  Future<Result<void>> setAssetActive({
    required String assetId,
    required bool active,
    required AuditActor actor,
  }) => _setActive(
    path: _assets,
    id: assetId,
    active: active,
    actor: actor,
    nameOf: (data) => data['name'] as String? ?? assetId,
  );

  Future<Result<void>> _setActive({
    required String path,
    required String id,
    required bool active,
    required AuditActor actor,
    required String Function(Map<String, dynamic>) nameOf,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(path).doc(id);
    final snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw FirestoreRepository.notFound('No $path $id');
    final data = snapshot.data() ?? const <String, dynamic>{};
    if (data['isActive'] == active) return;

    transaction.update(reference, {
      'isActive': active,
      'updatedAt': FirestoreRepository.serverNow,
    });
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.statusChanged,
      entityType: path,
      entityId: id,
      description: '${active ? 'Reactivated' : 'Deactivated'} ${nameOf(data)}',
      changes: {
        'isActive': {'from': !active, 'to': active},
      },
    );
  });

  Future<void> _requireFacility(
    Transaction transaction,
    String facilityId,
  ) async {
    final snapshot = await transaction.get(
      collection(_facilities).doc(facilityId),
    );
    if (!snapshot.exists) {
      throw FirestoreRepository.precondition('That room is not registered.');
    }
  }

  static Map<String, dynamic> _facilityFields(
    FacilityDraft draft,
    String code,
  ) => {
    // The building is what the report form and the reports show as the
    // facility's name, as the seed and 3.C have it.
    'name': draft.buildingName,
    'buildingName': draft.buildingName,
    'roomIdentifier': draft.roomIdentifier,
    'locationDescription':
        draft.locationDescription ??
        (draft.roomIdentifier == null
            ? null
            : '${draft.buildingName}, ${draft.roomIdentifier}'),
    'coordinates': switch ((draft.latitude, draft.longitude)) {
      (final latitude?, final longitude?) => GeoPoint(latitude, longitude),
      _ => null,
    },
    'qrCode': code,
  };

  static Map<String, dynamic> _assetFields(AssetDraft draft, String code) => {
    'name': draft.name,
    'facilityId': draft.facilityId,
    'condition': draft.condition.id,
    'category': draft.category,
    'serialNumber': draft.serialNumber,
    'qrCode': code,
  };

  static Map<String, dynamic> _changes(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) => {
    for (final MapEntry(:key, :value) in after.entries)
      if (before[key] != value)
        key: {'from': _plain(before[key]), 'to': _plain(value)},
  };

  /// A value an audit entry can hold: a GeoPoint as "lat, lng".
  static Object? _plain(Object? value) => switch (value) {
    final GeoPoint point => '${point.latitude}, ${point.longitude}',
    _ => value,
  };

  static String _placeName(FacilityDraft draft) =>
      [draft.buildingName, ?draft.roomIdentifier].join(', ');

  /// A failure saying [code] is taken, or null when it is free.
  Future<Failure?> _codeTaken(String code, {String? exceptId}) async {
    final owner = await guard.call(
      () => qrCodeOwner(db.raw, code, exceptId: exceptId),
    );
    return owner.fold(
      (owner) => owner == null
          ? null
          : ValidationFailure('The code $code is already on $owner.'),
      (failure) => failure,
    );
  }

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
