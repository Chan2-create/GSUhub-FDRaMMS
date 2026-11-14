import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/table_names.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/facilities/data/models/asset.dart';
import 'package:gsuhub/features/facilities/data/models/facility.dart';
import 'package:gsuhub/features/facilities/data/models/facility_draft.dart';
import 'package:gsuhub/features/facilities/data/repositories/facility_repository.dart';

import '../../../../core/data/firestore_records.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/data/qr_codes.dart';
import '../../../audit/data/repositories/audit_writes.dart';

/// Firestore-backed [FacilityRepository].
/// Objective 1 moved this data to Supabase; the app uses [FacilityRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreFacilityRepository extends FirestoreRepository
    implements FacilityRepository {
  const FirestoreFacilityRepository({required super.db, required super.guard});

  static const String _facilities = TableNames.facilities;
  static const String _assets = TableNames.assets;

  @override
  Future<Result<Facility>> getFacilityById(String id) =>
      getOne(path: _facilities, id: id, convert: fromDoc(Facility.fromRecord));

  @override
  Future<Result<Facility>> getFacilityByQrCode(String qrCode) => _firstByQrCode(
    path: _facilities,
    qrCode: qrCode,
    convert: fromDoc(Facility.fromRecord),
    label: 'facility',
  );

  @override
  Future<Result<List<Facility>>> getFacilities({bool activeOnly = true}) async {
    Query<Map<String, dynamic>> query = collection(_facilities);
    if (activeOnly) {
      query = query.where('isActive', isEqualTo: true);
    }
    return (await getMany(
      query: query,
      convert: fromDoc(Facility.fromRecord),
    )).map((rooms) => rooms.where((room) => !room.isDeleted).toList());
  }

  @override
  Stream<Result<List<Facility>>> watchFacilities() =>
      watchMany(
        query: collection(_facilities),
        convert: fromDoc(Facility.fromRecord),
      ).map(
        (result) => result.map(
          (facilities) =>
              [
                for (final facility in facilities)
                  if (!facility.isDeleted) facility,
              ]..sort((a, b) {
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

  /// As delete_facility: refused while open reports are about the room or
  /// equipment is in it (open work orders follow their reports here).
  @override
  Future<Result<void>> deleteFacility({
    required String facilityId,
    required AuditActor actor,
  }) async {
    final room = await getFacilityById(facilityId);
    if (room case Success(:final value) when !value.isDeleted) {
      final place = [value.buildingName, ?value.roomIdentifier].join(', ');
      if (await _openReports('facilityId', facilityId) case final count?
          when count > 0) {
        return Result.failure(
          ValidationFailure(
            '$place has $count open report${count == 1 ? '' : 's'}. '
            'Finish, reject or merge them first.',
          ),
        );
      }
      final equipment = await getAssetsForFacility(
        facilityId,
        activeOnly: false,
      );
      if (equipment case Success(value: final assets) when assets.isNotEmpty) {
        final count = assets.length;
        return Result.failure(
          ValidationFailure(
            '$place still has $count piece${count == 1 ? '' : 's'} of '
            'equipment. Delete it or move it to another room first.',
          ),
        );
      }
    }
    return _markDeleted(
      path: _facilities,
      id: facilityId,
      actor: actor,
      nameOf: (data) =>
          [data['buildingName'], ?data['roomIdentifier']].join(', '),
    );
  }

  @override
  Future<Result<Asset>> getAssetById(String id) =>
      getOne(path: _assets, id: id, convert: fromDoc(Asset.fromRecord));

  @override
  Future<Result<Asset>> getAssetByQrCode(String qrCode) => _firstByQrCode(
    path: _assets,
    qrCode: qrCode,
    convert: fromDoc(Asset.fromRecord),
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
    return getMany(query: query, convert: fromDoc(Asset.fromRecord)).then(
      (result) =>
          result.map((assets) => assets.where((a) => !a.isDeleted).toList()),
    );
  }

  @override
  Stream<Result<List<Asset>>> watchAssets() =>
      watchMany(
        query: collection(_assets),
        convert: fromDoc(Asset.fromRecord),
      ).map(
        (result) => result.map(
          (assets) =>
              [
                for (final asset in assets)
                  if (!asset.isDeleted) asset,
              ]..sort(
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

  @override
  Future<Result<void>> deleteAsset({
    required String assetId,
    required AuditActor actor,
  }) async {
    final asset = await getAssetById(assetId);
    if (asset case Success(:final value) when !value.isDeleted) {
      if (await _openReports('assetId', assetId) case final count?
          when count > 0) {
        return Result.failure(
          ValidationFailure(
            '${value.name} has $count open report${count == 1 ? '' : 's'}. '
            'Finish, reject or merge them first.',
          ),
        );
      }
    }
    return _markDeleted(
      path: _assets,
      id: assetId,
      actor: actor,
      nameOf: (data) => data['name'] as String? ?? assetId,
    );
  }

  /// How many open reports name [id] in [field]; null when unreadable.
  Future<int?> _openReports(String field, String id) async {
    final reports = await guard.call(
      () => db.raw
          .collection(TableNames.damageReports)
          .where(field, isEqualTo: id)
          .get(),
    );
    return reports.fold(
      (snapshot) => snapshot.docs
          .where(
            (doc) =>
                ReportStatus.values
                    .where((s) => s.id == doc.data()['status'])
                    .firstOrNull
                    ?.isOpen ??
                false,
          )
          .length,
      (_) => null,
    );
  }

  /// Marks a room or piece of equipment deleted, once, and audits it.
  Future<Result<void>> _markDeleted({
    required String path,
    required String id,
    required AuditActor actor,
    required String Function(Map<String, dynamic>) nameOf,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(path).doc(id);
    final snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw FirestoreRepository.notFound('No $path $id');
    final data = snapshot.data() ?? const <String, dynamic>{};
    if (data['deletedAt'] != null) return;

    transaction.update(reference, {
      'deletedAt': FirestoreRepository.serverNow,
      'updatedAt': FirestoreRepository.serverNow,
    });
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.deleted,
      entityType: path,
      entityId: id,
      description: 'Deleted ${nameOf(data)}',
    );
  });

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
    // A deleted one's code may be on one added since.
    final docs = await guard.call(
      () => collection(path).where('qrCode', isEqualTo: qrCode).get(),
    );
    final matches = docs.map(
      (snapshot) => [
        for (final doc in snapshot.docs)
          if (doc.data()['deletedAt'] == null) convert(doc),
      ],
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
