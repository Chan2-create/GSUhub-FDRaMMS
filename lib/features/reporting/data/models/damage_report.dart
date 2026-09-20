import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/firestore_converters.dart';

/// A `damage_reports` document — the facility damage report a requestor
/// submits, and the primary input to the whole maintenance lifecycle
/// (manuscript §1.7 "Facility Damage Report").
///
/// Carries three distinct notions of priority, which the manuscript keeps
/// deliberately separate (§1.2, §3.4):
///
/// 1. [requestorPriority] — what the requestor picked at submission, as
///    supplementary information only. Never authoritative.
/// 2. [recommendedPriority] / [priorityScore] — what the weighted
///    rule-based formula computed. Decision-support only.
/// 3. [officialPriority] — what the authorized GSU Administrator
///    confirmed or overrode. The only one that drives scheduling.
///
/// The four 1–4 criterion ratings that feed [priorityScore] are nullable
/// because **the manuscript never states who assigns them or when** — an
/// open question (development plan §2.2) still pending confirmation. See
/// docs/data_dictionary.md.
class DamageReport {
  DamageReport({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.title,
    required this.description,
    required this.requestorPriority,
    required this.status,
    required this.submittedAt,
    required this.updatedAt,
    this.category,
    this.classifiedAutomatically = false,
    this.facilityId,
    this.facilityName,
    this.locationDescription,
    this.assetId,
    this.coordinates,
    this.photoUrls = const [],
    this.severityRating,
    this.safetyRiskRating,
    this.frequencyRating,
    this.locationImportanceRating,
    this.priorityScore,
    this.recommendedPriority,
    this.officialPriority,
    this.duplicateOf,
    this.workOrderId,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
  }) {
    FirestoreConverters.validateNotBlank(reporterId, 'reporterId');
    FirestoreConverters.validateNotBlank(title, 'title');
    // Manuscript §3.4 Reporting Policy: "Each report must contain complete
    // and accurate information, including the description of the issue".
    FirestoreConverters.validateNotBlank(description, 'description');
    _validateRating(severityRating, 'severityRating');
    _validateRating(safetyRiskRating, 'safetyRiskRating');
    _validateRating(frequencyRating, 'frequencyRating');
    _validateRating(locationImportanceRating, 'locationImportanceRating');
    if (priorityScore != null) {
      // Bounds of the weighted formula when every criterion is rated 1–4
      // (manuscript Table 3.4 / Table 3.5).
      FirestoreConverters.validateRange(
        priorityScore!,
        1.0,
        4.0,
        'priorityScore',
      );
    }
  }

  factory DamageReport.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return DamageReport(
      id: doc.id,
      reporterId: FirestoreConverters.require<String>(data, 'reporterId'),
      reporterName: FirestoreConverters.require<String>(data, 'reporterName'),
      title: FirestoreConverters.require<String>(data, 'title'),
      description: FirestoreConverters.require<String>(data, 'description'),
      requestorPriority: FirestoreConverters.requireEnum(
        data,
        'requestorPriority',
        PriorityLevel.fromId,
      ),
      status: FirestoreConverters.requireEnum(
        data,
        'status',
        ReportStatus.fromId,
      ),
      category: FirestoreConverters.optionalEnum(
        data,
        'category',
        DamageCategory.fromId,
      ),
      classifiedAutomatically:
          FirestoreConverters.optional<bool>(data, 'classifiedAutomatically') ??
          false,
      facilityId: FirestoreConverters.optional<String>(data, 'facilityId'),
      facilityName: FirestoreConverters.optional<String>(data, 'facilityName'),
      locationDescription: FirestoreConverters.optional<String>(
        data,
        'locationDescription',
      ),
      assetId: FirestoreConverters.optional<String>(data, 'assetId'),
      coordinates: FirestoreConverters.optional<GeoPoint>(data, 'coordinates'),
      photoUrls: FirestoreConverters.stringList(data, 'photoUrls'),
      severityRating: FirestoreConverters.optional<int>(data, 'severityRating'),
      safetyRiskRating: FirestoreConverters.optional<int>(
        data,
        'safetyRiskRating',
      ),
      frequencyRating: FirestoreConverters.optional<int>(
        data,
        'frequencyRating',
      ),
      locationImportanceRating: FirestoreConverters.optional<int>(
        data,
        'locationImportanceRating',
      ),
      priorityScore: FirestoreConverters.optional<num>(
        data,
        'priorityScore',
      )?.toDouble(),
      recommendedPriority: FirestoreConverters.optionalEnum(
        data,
        'recommendedPriority',
        PriorityLevel.fromId,
      ),
      officialPriority: FirestoreConverters.optionalEnum(
        data,
        'officialPriority',
        PriorityLevel.fromId,
      ),
      duplicateOf: FirestoreConverters.optional<String>(data, 'duplicateOf'),
      workOrderId: FirestoreConverters.optional<String>(data, 'workOrderId'),
      reviewedBy: FirestoreConverters.optional<String>(data, 'reviewedBy'),
      reviewedAt: FirestoreConverters.optionalDate(data, 'reviewedAt'),
      rejectionReason: FirestoreConverters.optional<String>(
        data,
        'rejectionReason',
      ),
      submittedAt: FirestoreConverters.requireDate(data, 'submittedAt'),
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
    );
  }

  static void _validateRating(int? value, String field) {
    if (value == null) return;
    FirestoreConverters.validateRange(value, 1, 4, field);
  }

  final String id;

  final String reporterId;

  /// DENORMALIZED from `users.fullName` — lets the Admin report table
  /// (manuscript Figure 16, "REPORTER" column) render without an N+1
  /// lookup per row. Written at submission; refreshed if the user renames.
  final String reporterName;

  /// Short summary shown in list views (Figure 21, "FACILITY / ISSUE
  /// TITLE").
  final String title;

  final String description;

  /// Set by the rule-based classifier, or by an Administrator when no
  /// keyword matched. Null until classified — manuscript §3.4: reports
  /// that match no keyword "are forwarded to the authorized GSU
  /// Administrator for manual review and classification".
  final DamageCategory? category;

  /// Whether [category] came from keyword matching (`true`) or an
  /// Administrator's manual classification (`false`). Lets 4.A measure
  /// how often the keyword dictionary actually fires.
  final bool classifiedAutomatically;

  final String? facilityId;

  /// DENORMALIZED from `facilities.name` — same read-performance reason as
  /// [reporterName] (Figure 16, "LOCATION" column).
  final String? facilityName;

  final String? locationDescription;

  /// Set when the requestor scanned an asset's QR code rather than only
  /// naming a facility.
  final String? assetId;

  /// Device GPS at submission. Explicitly supplementary — manuscript §2.2:
  /// geo-tagging "does not replace the requestor's own location details".
  final GeoPoint? coordinates;

  /// Cloud Storage download URLs for photo evidence.
  final List<String> photoUrls;

  /// The requestor's own urgency selection (§1.2). Supplementary; does not
  /// determine [officialPriority].
  final PriorityLevel requestorPriority;

  /// 1–4 weighted-formula criteria (manuscript Table 3.4). All nullable —
  /// population path pending (§2.2).
  final int? severityRating;
  final int? safetyRiskRating;
  final int? frequencyRating;
  final int? locationImportanceRating;

  /// Computed weighted score, 1.00–4.00. Null until the criteria above are
  /// populated and 4.B computes it.
  final double? priorityScore;

  /// [priorityScore] mapped through the Table 3.5 thresholds. Decision
  /// support only.
  final PriorityLevel? recommendedPriority;

  /// The Administrator's confirmed or modified priority — the only
  /// authoritative one (§1.2). Null until reviewed.
  final PriorityLevel? officialPriority;

  final ReportStatus status;

  /// Set when this report was merged into another as a duplicate. The
  /// merged report keeps its own document and id (manuscript §3.4:
  /// administrators may "merge, dismiss, or retain" flagged duplicates).
  final String? duplicateOf;

  /// The work order raised from this report. Several reports can point at
  /// the same work order — see `WorkOrder.reportIds`.
  final String? workOrderId;

  final String? reviewedBy;
  final DateTime? reviewedAt;

  /// Why an administrator rejected the report. Required on rejection and
  /// null otherwise: a dismissed report with no recorded reason tells the
  /// requestor nothing and leaves no trail for the next reviewer.
  final String? rejectionReason;

  final DateTime submittedAt;
  final DateTime updatedAt;

  /// Whether this report was merged into another and should be hidden from
  /// active queues.
  bool get isDuplicate => duplicateOf != null;

  /// The priority that should actually drive scheduling: the
  /// Administrator's decision once made, falling back to the computed
  /// recommendation, then to the requestor's own selection.
  PriorityLevel get effectivePriority =>
      officialPriority ?? recommendedPriority ?? requestorPriority;

  /// Whether an administrator has confirmed the official priority. Until
  /// then [effectivePriority] is only a suggestion, and the UI marks it as
  /// one.
  bool get isPriorityConfirmed => officialPriority != null;

  Map<String, dynamic> toFirestore() => {
    'reporterId': reporterId,
    'reporterName': reporterName,
    'title': title,
    'description': description,
    'category': category?.id,
    'classifiedAutomatically': classifiedAutomatically,
    'facilityId': facilityId,
    'facilityName': facilityName,
    'locationDescription': locationDescription,
    'assetId': assetId,
    'coordinates': coordinates,
    'photoUrls': photoUrls,
    'requestorPriority': requestorPriority.id,
    'severityRating': severityRating,
    'safetyRiskRating': safetyRiskRating,
    'frequencyRating': frequencyRating,
    'locationImportanceRating': locationImportanceRating,
    'priorityScore': priorityScore,
    'recommendedPriority': recommendedPriority?.id,
    'officialPriority': officialPriority?.id,
    'status': status.id,
    'duplicateOf': duplicateOf,
    'workOrderId': workOrderId,
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt == null ? null : Timestamp.fromDate(reviewedAt!),
    'rejectionReason': rejectionReason,
    'submittedAt': Timestamp.fromDate(submittedAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  DamageReport copyWith({
    String? id,
    String? reporterId,
    String? reporterName,
    String? title,
    String? description,
    DamageCategory? category,
    bool? classifiedAutomatically,
    String? facilityId,
    String? facilityName,
    String? locationDescription,
    String? assetId,
    GeoPoint? coordinates,
    List<String>? photoUrls,
    PriorityLevel? requestorPriority,
    int? severityRating,
    int? safetyRiskRating,
    int? frequencyRating,
    int? locationImportanceRating,
    double? priorityScore,
    PriorityLevel? recommendedPriority,
    PriorityLevel? officialPriority,
    ReportStatus? status,
    String? duplicateOf,
    String? workOrderId,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? rejectionReason,
    DateTime? submittedAt,
    DateTime? updatedAt,
  }) => DamageReport(
    id: id ?? this.id,
    reporterId: reporterId ?? this.reporterId,
    reporterName: reporterName ?? this.reporterName,
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    classifiedAutomatically:
        classifiedAutomatically ?? this.classifiedAutomatically,
    facilityId: facilityId ?? this.facilityId,
    facilityName: facilityName ?? this.facilityName,
    locationDescription: locationDescription ?? this.locationDescription,
    assetId: assetId ?? this.assetId,
    coordinates: coordinates ?? this.coordinates,
    photoUrls: photoUrls ?? this.photoUrls,
    requestorPriority: requestorPriority ?? this.requestorPriority,
    severityRating: severityRating ?? this.severityRating,
    safetyRiskRating: safetyRiskRating ?? this.safetyRiskRating,
    frequencyRating: frequencyRating ?? this.frequencyRating,
    locationImportanceRating:
        locationImportanceRating ?? this.locationImportanceRating,
    priorityScore: priorityScore ?? this.priorityScore,
    recommendedPriority: recommendedPriority ?? this.recommendedPriority,
    officialPriority: officialPriority ?? this.officialPriority,
    status: status ?? this.status,
    duplicateOf: duplicateOf ?? this.duplicateOf,
    workOrderId: workOrderId ?? this.workOrderId,
    reviewedBy: reviewedBy ?? this.reviewedBy,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    submittedAt: submittedAt ?? this.submittedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DamageReport) return false;
    return other.id == id &&
        other.reporterId == reporterId &&
        other.reporterName == reporterName &&
        other.title == title &&
        other.description == description &&
        other.category == category &&
        other.classifiedAutomatically == classifiedAutomatically &&
        other.facilityId == facilityId &&
        other.facilityName == facilityName &&
        other.locationDescription == locationDescription &&
        other.assetId == assetId &&
        other.coordinates == coordinates &&
        listEquals(other.photoUrls, photoUrls) &&
        other.requestorPriority == requestorPriority &&
        other.severityRating == severityRating &&
        other.safetyRiskRating == safetyRiskRating &&
        other.frequencyRating == frequencyRating &&
        other.locationImportanceRating == locationImportanceRating &&
        other.priorityScore == priorityScore &&
        other.recommendedPriority == recommendedPriority &&
        other.officialPriority == officialPriority &&
        other.status == status &&
        other.duplicateOf == duplicateOf &&
        other.workOrderId == workOrderId &&
        other.reviewedBy == reviewedBy &&
        other.reviewedAt == reviewedAt &&
        other.rejectionReason == rejectionReason &&
        other.submittedAt == submittedAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    reporterId,
    reporterName,
    title,
    description,
    category,
    classifiedAutomatically,
    facilityId,
    facilityName,
    locationDescription,
    assetId,
    coordinates,
    ...photoUrls,
    requestorPriority,
    severityRating,
    safetyRiskRating,
    frequencyRating,
    locationImportanceRating,
    priorityScore,
    recommendedPriority,
    officialPriority,
    status,
    duplicateOf,
    workOrderId,
    reviewedBy,
    reviewedAt,
    rejectionReason,
    submittedAt,
    updatedAt,
  ]);

  @override
  String toString() =>
      'DamageReport(id: $id, title: $title, category: $category, '
      'status: $status, effectivePriority: $effectivePriority)';
}
