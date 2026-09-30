import 'dart:async';
import 'dart:typed_data';

import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/location_service.dart';
import 'package:gsuhub/core/services/photo_picker_service.dart';
import 'package:gsuhub/core/services/storage_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/facilities/data/models/asset.dart';
import 'package:gsuhub/features/facilities/data/models/facility.dart';
import 'package:gsuhub/features/facilities/data/repositories/facility_repository.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/models/report_submission.dart';
import 'package:gsuhub/features/reporting/data/repositories/damage_report_repository.dart';

/// Stand-ins for everything the damage report form talks to (3.C): the
/// camera, the GPS, Storage, the facility registry and the report
/// repository — each scripted to answer as a test needs, and each keeping
/// a record of what was asked of it.

PickedPhoto fakePhoto({int bytes = 1024, String name = 'IMG_0001.jpg'}) =>
    PickedPhoto(
      bytes: Uint8List(bytes),
      fileName: name,
      mimeType: 'image/jpeg',
    );

class FakePhotoPicker implements PhotoPickerService {
  FakePhotoPicker({List<PickedPhoto>? photos, this.failure})
    : photos = photos ?? [fakePhoto()];

  /// What the next pick returns (trimmed to the limit, as a real picker
  /// would be).
  List<PickedPhoto> photos;

  /// When set, picking fails with this instead.
  Failure? failure;

  final requests = <({PhotoSource source, int limit})>[];

  @override
  Future<Result<List<PickedPhoto>>> pick(
    PhotoSource source, {
    required int limit,
  }) async {
    requests.add((source: source, limit: limit));
    if (failure case final failure?) return Result.failure(failure);
    return Result.success(photos.take(limit).toList());
  }
}

class FakeLocationService implements LocationService {
  FakeLocationService({this.result = const Result.success(campus)});

  static const campus = GeoCoordinates(
    latitude: 7.2048,
    longitude: 126.5354,
    accuracyMeters: 9,
  );

  Result<GeoCoordinates> result;

  /// When set, the reading waits for this before answering — for testing
  /// what happens while the device is still locating.
  Completer<void>? gate;

  int calls = 0;

  @override
  Future<Result<GeoCoordinates>> currentPosition() async {
    calls++;
    await gate?.future;
    return result;
  }
}

class FakeStorageService implements StorageService {
  /// Paths whose upload fails, with the failure.
  final failures = <bool Function(String path), Failure>{};

  final uploadedPaths = <String>[];

  @override
  UploadTaskHandle uploadFileWithProgress({
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) {
    for (final entry in failures.entries) {
      if (entry.key(path)) {
        return UploadTaskHandle(
          progress: const Stream.empty(),
          downloadUrl: Future.value(Result.failure(entry.value)),
        );
      }
    }
    uploadedPaths.add(path);
    return UploadTaskHandle(
      progress: Stream.fromIterable([
        UploadProgress(bytesTransferred: 0, totalBytes: bytes.length),
        UploadProgress(
          bytesTransferred: bytes.length,
          totalBytes: bytes.length,
        ),
      ]),
      downloadUrl: Future.value(Result.success('https://storage.test/$path')),
    );
  }

  @override
  Future<Result<String>> uploadFile({
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) => uploadFileWithProgress(
    path: path,
    bytes: bytes,
    contentType: contentType,
  ).downloadUrl;

  @override
  Future<Result<String>> getDownloadUrl({required String path}) async =>
      Result.success('https://storage.test/$path');

  @override
  Future<Result<void>> deleteFile({required String path}) async =>
      const Result.success(null);
}

class FakeSubmittingReportRepository implements DamageReportRepository {
  FakeSubmittingReportRepository({
    this.submitResult = const Result.success(null),
  });

  /// What [submit] answers.
  Result<void> submitResult;

  int _reserved = 0;
  final submissions = <({String reportId, ReportSubmission submission})>[];

  /// The [n]th id this fake reserves: 20 characters and no dashes, like a
  /// Firestore auto id, so it is displayed as one (`#DR-…`).
  static String idFor(int n) => 'autoReportId${'$n'.padLeft(8, '0')}';

  @override
  String newReportId() => idFor(++_reserved);

  @override
  Future<Result<void>> submit({
    required String reportId,
    required ReportSubmission submission,
  }) async {
    submissions.add((reportId: reportId, submission: submission));
    return submitResult;
  }

  @override
  Stream<Result<List<DamageReport>>> watchByReporter(String reporterId) =>
      Stream.value(const Result.success([]));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Facility fakeFacility({
  required String id,
  required String building,
  String? room,
  bool isActive = true,
}) => Facility(
  id: id,
  name: building,
  buildingName: building,
  roomIdentifier: room,
  locationDescription: room == null ? null : '$building, $room',
  qrCode: 'FAC-${id.toUpperCase()}',
  isActive: isActive,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class FakeFacilityRepository implements FacilityRepository {
  FakeFacilityRepository({
    List<Facility>? facilities,
    this.assets = const [],
    this.failure,
  }) : facilities =
           facilities ??
           [
             fakeFacility(
               id: 'fac-eng-101',
               building: 'Engineering Building',
               room: 'Room 101',
             ),
             fakeFacility(
               id: 'fac-eng-203',
               building: 'Engineering Building',
               room: 'Room 203',
             ),
             fakeFacility(
               id: 'fac-library',
               building: 'Main Library',
               room: 'Level 2',
             ),
           ];

  final List<Facility> facilities;
  final List<Asset> assets;

  /// When set, every read fails with this.
  final Failure? failure;

  @override
  Future<Result<List<Facility>>> getFacilities({bool activeOnly = true}) async {
    if (failure case final failure?) return Result.failure(failure);
    return Result.success([
      for (final facility in facilities)
        if (!activeOnly || facility.isActive) facility,
    ]);
  }

  @override
  Future<Result<Facility>> getFacilityById(String id) async =>
      _find(facilities, (facility) => facility.id == id);

  @override
  Future<Result<Facility>> getFacilityByQrCode(String qrCode) async =>
      _find(facilities, (facility) => facility.qrCode == qrCode);

  @override
  Future<Result<Asset>> getAssetByQrCode(String qrCode) async =>
      _find(assets, (asset) => asset.qrCode == qrCode);

  Result<T> _find<T>(List<T> items, bool Function(T) test) {
    if (failure case final failure?) return Result.failure(failure);
    for (final item in items) {
      if (test(item)) return Result.success(item);
    }
    return const Result.failure(NotFoundFailure('Not found.'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
