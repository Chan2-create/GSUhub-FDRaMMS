import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/constants/storage_paths.dart';
import '../../../../core/di/repository_providers.dart';
import '../../../../core/di/service_providers.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/photo_picker_service.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/presentation/current_actor_provider.dart';
import '../../../facilities/data/models/facility.dart';
import '../../../facilities/presentation/facility_directory.dart';
import '../../../facilities/presentation/qr_lookup.dart';
import '../../data/models/report_submission.dart';
import 'report_form_state.dart';

/// Drives the damage report form (Objective 3.C): the draft, its
/// validation, photos, the geo-tag, QR lookup, and the two-step send —
/// photos to Storage, then the report to Firestore.
///
/// Talks only to interfaces (repositories, `StorageService`,
/// `LocationService`, `PhotoPickerService`), so every path through it is
/// testable without a device.
class ReportFormController extends Notifier<ReportFormState> {
  /// Most photos one report takes.
  static const int maxPhotos = 5;

  /// Mirrors the 10 MB ceiling in `firebase/storage.rules`, so an oversized
  /// photo is turned away on the form rather than failing mid-upload.
  static const int maxPhotoBytes = 10 * 1024 * 1024;

  int _nextPhotoId = 0;

  @override
  ReportFormState build() => const ReportFormState();

  void setTitle(String title) => _edit(state.copyWith(title: title));

  void setDescription(String description) =>
      _edit(state.copyWith(description: description));

  void setUrgency(PriorityLevel urgency) =>
      _edit(state.copyWith(urgency: urgency));

  /// Null takes the suggestion back ("Not sure").
  void setDamageType(DamageCategory? type) =>
      _edit(state.copyWith(damageType: type, clearDamageType: type == null));

  /// Choosing another building clears the room, which belonged to the old
  /// one — and any scanned asset with it.
  void selectBuilding(String building) {
    if (building == state.building) return;
    _edit(
      state.copyWith(building: building, clearFacility: true, clearAsset: true),
    );
  }

  void selectRoom(Facility facility) => _edit(
    state.copyWith(
      building: facility.buildingName,
      facility: facility,
      // A scanned asset stays only while its own room is the one chosen.
      clearAsset: state.asset?.facilityId != facility.id,
    ),
  );

  /// Adds photos from [source]. Returns a message for the screen to show
  /// when some or all could not be added, else null.
  Future<String?> addPhotos(PhotoSource source) async {
    if (state.isLocked) return null;
    final room = maxPhotos - state.photos.length;
    if (room <= 0) return 'A report can have up to $maxPhotos photos.';

    final result = await ref
        .read(photoPickerServiceProvider)
        .pick(source, limit: room);
    if (!ref.mounted || state.isLocked) return null;

    switch (result) {
      case Error(:final failure):
        return failure.message;
      case Success(value: final picked):
        final fitting = [
          for (final photo in picked)
            if (photo.sizeInBytes < maxPhotoBytes) photo,
        ];
        // Space is counted again: the picker was open long enough for the
        // requestor to have added photos another way.
        final space = maxPhotos - state.photos.length;
        state = state.copyWith(
          photos: [
            ...state.photos,
            for (final photo in fitting.take(space))
              DraftPhoto(id: _nextPhotoId++, photo: photo),
          ],
        );
        final tooLarge = picked.length - fitting.length;
        if (tooLarge > 0) {
          return tooLarge == 1
              ? 'That photo is over 10 MB, so it was left out.'
              : '$tooLarge photos are over 10 MB, so they were left out.';
        }
        if (fitting.length > space) {
          return 'A report can have up to $maxPhotos photos, so '
              '${fitting.length - space} were left out.';
        }
        return null;
    }
  }

  void removePhoto(int id) => _edit(
    state.copyWith(photos: [...state.photos.where((photo) => photo.id != id)]),
  );

  /// Switches the geo-tag on — asking the device for a position — or off.
  Future<void> setGeoTag({required bool enabled}) async {
    if (state.isLocked) return;
    if (!enabled) {
      state = state.copyWith(
        geoTagStatus: GeoTagStatus.off,
        clearCoordinates: true,
        clearGeoTagMessage: true,
      );
      return;
    }
    await refreshLocation();
  }

  /// Takes a fresh reading, for when the first was poor or the requestor
  /// has moved to the damage since opening the form.
  Future<void> refreshLocation() async {
    if (state.isLocked) return;
    state = state.copyWith(
      geoTagStatus: GeoTagStatus.locating,
      clearGeoTagMessage: true,
    );

    final result = await ref.read(locationServiceProvider).currentPosition();
    // The requestor may have switched the geo-tag off while waiting.
    if (!ref.mounted || state.geoTagStatus != GeoTagStatus.locating) return;

    state = switch (result) {
      Success(value: final coordinates) => state.copyWith(
        geoTagStatus: GeoTagStatus.attached,
        coordinates: coordinates,
      ),
      Error(:final failure) => state.copyWith(
        geoTagStatus: GeoTagStatus.unavailable,
        geoTagMessage: failure.message,
        clearCoordinates: true,
      ),
    };
  }

  /// Sets the geo-tag to a point the requestor placed on the map ("Tap to
  /// adjust location on map"). Indoors a GPS fix can be tens of metres
  /// out (§2.2); the requestor standing at the damage knows better.
  void pinLocation(GeoCoordinates point) {
    if (state.isLocked) return;
    state = state.copyWith(
      geoTagStatus: GeoTagStatus.attached,
      coordinates: point,
      clearGeoTagMessage: true,
    );
  }

  /// Fills in the building and room from a scanned QR code, and the asset
  /// when the code was on one. The result is returned for the screen to
  /// confirm, or to say why the code was not recognised.
  Future<Result<QrMatch>> applyQrCode(String code) async {
    final result = await ref.read(qrLookupProvider).resolve(code);
    if (!ref.mounted || state.isLocked) return result;

    if (result case Success(value: final match)) {
      state = state.copyWith(
        building: match.facility.buildingName,
        facility: match.facility,
        asset: match.asset,
        clearAsset: match.asset == null,
      );
    }
    return result;
  }

  /// Sends the report: each photo not yet uploaded, then the report.
  ///
  /// The report id is reserved once and kept, so after a failure the next
  /// attempt skips the photos already sent and — through the repository's
  /// idempotent submit — can never file the report twice.
  Future<void> submit() async {
    if (state.isLocked) return;
    if (state.errors.isNotEmpty) {
      state = state.copyWith(showErrors: true);
      return;
    }

    final reporter = await ref.read(currentActorProvider.future);
    if (!ref.mounted) return;
    if (reporter == null) {
      state = state.copyWith(
        phase: const SubmissionFailed(
          'Your session has expired. Please sign in again.',
        ),
      );
      return;
    }

    final reports = ref.read(damageReportRepositoryProvider);
    final reportId = state.reportId ?? reports.newReportId();
    state = state.copyWith(reportId: reportId, showErrors: true);

    // --- photos ---
    final storage = ref.read(storageServiceProvider);
    final total = state.photos.length;
    for (var index = 0; index < total; index++) {
      final draft = state.photos[index];
      if (draft.isUploaded) continue;

      state = state.copyWith(
        phase: SubmissionUploading(
          current: index + 1,
          total: total,
          fraction: index / total,
        ),
      );

      final upload = storage.uploadFileWithProgress(
        // Unique per attempt: an upload can reach Storage and still fail
        // on the way back, and the rules refuse overwriting a file, so a
        // retry under the same name would fail for good.
        path: StoragePaths.damageReportPhoto(
          reportId,
          'photo-${draft.id + 1}-${DateTime.now().millisecondsSinceEpoch}'
          '${_extensionOf(draft.photo.mimeType)}',
        ),
        bytes: draft.photo.bytes,
        contentType: draft.photo.mimeType,
      );
      final progress = upload.progress.listen((event) {
        if (!ref.mounted) return;
        state = state.copyWith(
          phase: SubmissionUploading(
            current: index + 1,
            total: total,
            fraction: (index + event.fraction) / total,
          ),
        );
      });
      final url = await upload.downloadUrl;
      // Cleanup only, so not awaited: a progress stream's cancel can wait
      // on the stream it is cancelling, and the report must not.
      unawaited(progress.cancel());
      if (!ref.mounted) return;

      switch (url) {
        case Error(:final failure):
          state = state.copyWith(
            phase: SubmissionFailed(
              "Photo ${index + 1} of $total didn't upload. "
              '${failure.message}',
            ),
          );
          return;
        case Success(value: final downloadUrl):
          final photos = [...state.photos];
          photos[index] = draft.uploaded(downloadUrl);
          state = state.copyWith(photos: photos);
      }
    }

    // --- the report ---
    state = state.copyWith(phase: const SubmissionSaving());
    final facility = state.facility!;
    final result = await reports.submit(
      reportId: reportId,
      submission: ReportSubmission(
        reporter: reporter,
        title: state.title,
        description: state.description,
        requestorPriority: state.urgency!,
        requestorCategory: state.damageType,
        facilityId: facility.id,
        facilityName: facility.name,
        locationDescription:
            facility.locationDescription ??
            '${facility.buildingName}, '
                '${FacilityDirectory.roomLabelOf(facility)}',
        assetId: state.asset?.id,
        coordinates: state.geoTagStatus == GeoTagStatus.attached
            ? state.coordinates
            : null,
        photoUrls: [for (final photo in state.photos) photo.uploadedUrl!],
      ),
    );
    if (!ref.mounted) return;

    state = state.copyWith(
      phase: switch (result) {
        Success() => SubmissionDone(reportId),
        Error(:final failure) => SubmissionFailed(failure.message),
      },
    );
  }

  /// Applies an edit unless the form is locked, and returns a failed
  /// submission to editing — the requestor is fixing what went wrong.
  void _edit(ReportFormState next) {
    if (state.isLocked) return;
    state = next.phase is SubmissionFailed
        ? next.copyWith(phase: const SubmissionEditing())
        : next;
  }

  static String _extensionOf(String mimeType) => switch (mimeType) {
    'image/png' => '.png',
    'image/webp' => '.webp',
    'image/gif' => '.gif',
    'image/heic' => '.heic',
    _ => '.jpg',
  };
}

/// Disposed with the form, so leaving and coming back starts a clean one.
final reportFormControllerProvider =
    NotifierProvider.autoDispose<ReportFormController, ReportFormState>(
      ReportFormController.new,
    );
