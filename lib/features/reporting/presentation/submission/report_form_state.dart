import 'package:flutter/foundation.dart';

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/photo_picker_service.dart';
import '../../../facilities/data/models/asset.dart';
import '../../../facilities/data/models/facility.dart';

/// The fields of the report form that can be wrong, for pinning a message
/// under the right one.
enum ReportField { title, urgency, description, photos, building, room }

/// One photo on the form. Carries its download URL once uploaded, so a
/// retry after a failed submission does not upload it again.
@immutable
class DraftPhoto {
  const DraftPhoto({required this.id, required this.photo, this.uploadedUrl});

  /// Stable within one form, for keys and removal.
  final int id;
  final PickedPhoto photo;
  final String? uploadedUrl;

  bool get isUploaded => uploadedUrl != null;

  DraftPhoto uploaded(String url) =>
      DraftPhoto(id: id, photo: photo, uploadedUrl: url);
}

/// Where the geo-tag stands.
enum GeoTagStatus {
  /// The requestor has not asked for one.
  off,

  /// Waiting on the device for a fix.
  locating,

  /// A position is attached.
  attached,

  /// The device could not give one; [ReportFormState.geoTagMessage] says
  /// why. The report can still be submitted.
  unavailable,
}

/// How far a submission has got.
sealed class SubmissionPhase {
  const SubmissionPhase();

  bool get isBusy => this is SubmissionUploading || this is SubmissionSaving;
}

/// Filling in the form.
final class SubmissionEditing extends SubmissionPhase {
  const SubmissionEditing();
}

/// Sending photo [current] of [total]; [fraction] is 0–1 across all of
/// them, for one determinate bar.
final class SubmissionUploading extends SubmissionPhase {
  const SubmissionUploading({
    required this.current,
    required this.total,
    required this.fraction,
  });

  final int current;
  final int total;
  final double fraction;
}

/// Photos are up; filing the report itself.
final class SubmissionSaving extends SubmissionPhase {
  const SubmissionSaving();
}

/// Filed.
final class SubmissionDone extends SubmissionPhase {
  const SubmissionDone(this.reportId);

  final String reportId;
}

/// Stopped with [message]. The form keeps everything, including the
/// photos already sent, so trying again resumes rather than restarts.
final class SubmissionFailed extends SubmissionPhase {
  const SubmissionFailed(this.message);

  final String message;
}

/// Everything on the report form (Objective 3.C).
@immutable
class ReportFormState {
  const ReportFormState({
    this.title = '',
    this.description = '',
    this.damageType,
    this.urgency,
    this.building,
    this.facility,
    this.asset,
    this.photos = const [],
    this.geoTagStatus = GeoTagStatus.off,
    this.coordinates,
    this.geoTagMessage,
    this.reportId,
    this.phase = const SubmissionEditing(),
    this.showErrors = false,
  });

  final String title;
  final String description;

  /// The requestor's suggested damage type. Optional — a suggestion for
  /// the classifier and the Administrator, who decide the category.
  final DamageCategory? damageType;

  /// The requestor's own sense of urgency (§1.2).
  final PriorityLevel? urgency;

  final String? building;

  /// The room — a facility in [building].
  final Facility? facility;

  /// Set only by scanning an asset's QR code.
  final Asset? asset;

  final List<DraftPhoto> photos;

  final GeoTagStatus geoTagStatus;
  final GeoCoordinates? coordinates;

  /// Why the device gave no position, when it did not.
  final String? geoTagMessage;

  /// Reserved on the first attempt to submit and kept for retries, so the
  /// photos already uploaded stay under the report they belong to — and a
  /// retry can never file a second report.
  final String? reportId;

  final SubmissionPhase phase;

  /// Validation messages appear only once the requestor has tried to
  /// submit: a form that opens covered in red has not been given a chance.
  final bool showErrors;

  bool get geoTagEnabled => geoTagStatus != GeoTagStatus.off;

  /// Nothing on the form changes while a submission is in flight, or after
  /// it has been filed.
  bool get isLocked => phase.isBusy || phase is SubmissionDone;

  /// What is missing, field by field. Empty when the form can be sent.
  Map<ReportField, String> get errors => {
    if (title.trim().isEmpty)
      ReportField.title: 'Give the damage a short title.',
    if (urgency == null) ReportField.urgency: 'Choose how urgent this is.',
    // §3.4 Reporting Policy: each report must include "the description of
    // the issue".
    if (description.trim().isEmpty)
      ReportField.description: 'Describe the damage.',
    // §1.5: reports carry photo evidence.
    if (photos.isEmpty) ReportField.photos: 'Add at least one photo.',
    if (building == null) ReportField.building: 'Choose the building.',
    if (building != null && facility == null)
      ReportField.room: 'Choose the room.',
  };

  /// The message to show under [field], if any.
  String? errorFor(ReportField field) => showErrors ? errors[field] : null;

  ReportFormState copyWith({
    String? title,
    String? description,
    DamageCategory? damageType,
    PriorityLevel? urgency,
    String? building,
    Facility? facility,
    Asset? asset,
    List<DraftPhoto>? photos,
    GeoTagStatus? geoTagStatus,
    GeoCoordinates? coordinates,
    String? geoTagMessage,
    String? reportId,
    SubmissionPhase? phase,
    bool? showErrors,
    bool clearDamageType = false,
    bool clearFacility = false,
    bool clearAsset = false,
    bool clearCoordinates = false,
    bool clearGeoTagMessage = false,
  }) => ReportFormState(
    title: title ?? this.title,
    description: description ?? this.description,
    damageType: clearDamageType ? null : damageType ?? this.damageType,
    urgency: urgency ?? this.urgency,
    building: building ?? this.building,
    facility: clearFacility ? null : facility ?? this.facility,
    asset: clearAsset ? null : asset ?? this.asset,
    photos: photos ?? this.photos,
    geoTagStatus: geoTagStatus ?? this.geoTagStatus,
    coordinates: clearCoordinates ? null : coordinates ?? this.coordinates,
    geoTagMessage: clearGeoTagMessage
        ? null
        : geoTagMessage ?? this.geoTagMessage,
    reportId: reportId ?? this.reportId,
    phase: phase ?? this.phase,
    showErrors: showErrors ?? this.showErrors,
  );
}
