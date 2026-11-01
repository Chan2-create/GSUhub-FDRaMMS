import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/data/data_record.dart';
import '../../../../core/utils/record_converters.dart';
import 'material_usage.dart';

/// An `accomplishment_reports` document — what maintenance personnel
/// submit when work is finished: "completion notes and upload photo
/// documentation of completed work" (manuscript §1.5; Figure 23 shows a
/// Completion Notes field, a photo evidence grid, and a Mark Complete
/// action).
///
/// Submitting one is the event that triggers automatic inventory
/// deduction (§3.4) — see [materialsUsed].
class AccomplishmentReport {
  AccomplishmentReport({
    required this.id,
    required this.workOrderId,
    required this.submittedBy,
    required this.completionNotes,
    required this.submittedAt,
    this.photoUrls = const [],
    this.materialsUsed = const [],
    this.inventoryDeducted = false,
    this.reviewedBy,
    this.reviewedAt,
  }) {
    RecordConverters.validateNotBlank(workOrderId, 'workOrderId');
    RecordConverters.validateNotBlank(submittedBy, 'submittedBy');
    RecordConverters.validateNotBlank(completionNotes, 'completionNotes');
  }

  factory AccomplishmentReport.fromRecord(DataRecord record) {
    final data = record.fields;
    final rawMaterials = data['materialsUsed'];
    return AccomplishmentReport(
      id: record.id,
      workOrderId: RecordConverters.require<String>(data, 'workOrderId'),
      submittedBy: RecordConverters.require<String>(data, 'submittedBy'),
      completionNotes: RecordConverters.require<String>(
        data,
        'completionNotes',
      ),
      photoUrls: RecordConverters.stringList(data, 'photoUrls'),
      materialsUsed: rawMaterials is List
          ? rawMaterials
                .map(
                  (entry) =>
                      MaterialUsage.fromMap(entry as Map<String, dynamic>),
                )
                .toList(growable: false)
          : const [],
      inventoryDeducted:
          RecordConverters.optional<bool>(data, 'inventoryDeducted') ?? false,
      reviewedBy: RecordConverters.optional<String>(data, 'reviewedBy'),
      reviewedAt: RecordConverters.optionalDate(data, 'reviewedAt'),
      submittedAt: RecordConverters.requireDate(data, 'submittedAt'),
    );
  }

  final String id;
  final String workOrderId;

  /// The maintenance personnel account that submitted this report.
  final String submittedBy;

  final String completionNotes;

  /// Cloud Storage download URLs for completed-work photo documentation.
  final List<String> photoUrls;

  /// Materials consumed during this job. Each entry becomes a
  /// `consumption` transaction in the append-only inventory ledger.
  final List<MaterialUsage> materialsUsed;

  /// Guard flag for the automatic deduction described in §3.4: set once
  /// the corresponding `inventory_transactions` records have been written,
  /// so a retry or a duplicate submission cannot deduct the same materials
  /// twice. DERIVED — the manuscript describes the deduction but not the
  /// idempotency concern. See docs/data_dictionary.md.
  final bool inventoryDeducted;

  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime submittedAt;

  Map<String, dynamic> toFields() => {
    'workOrderId': workOrderId,
    'submittedBy': submittedBy,
    'completionNotes': completionNotes,
    'photoUrls': photoUrls,
    'materialsUsed': materialsUsed
        .map((material) => material.toMap())
        .toList(growable: false),
    'inventoryDeducted': inventoryDeducted,
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt,
    'submittedAt': submittedAt,
  };

  AccomplishmentReport copyWith({
    String? id,
    String? workOrderId,
    String? submittedBy,
    String? completionNotes,
    List<String>? photoUrls,
    List<MaterialUsage>? materialsUsed,
    bool? inventoryDeducted,
    String? reviewedBy,
    DateTime? reviewedAt,
    DateTime? submittedAt,
  }) => AccomplishmentReport(
    id: id ?? this.id,
    workOrderId: workOrderId ?? this.workOrderId,
    submittedBy: submittedBy ?? this.submittedBy,
    completionNotes: completionNotes ?? this.completionNotes,
    photoUrls: photoUrls ?? this.photoUrls,
    materialsUsed: materialsUsed ?? this.materialsUsed,
    inventoryDeducted: inventoryDeducted ?? this.inventoryDeducted,
    reviewedBy: reviewedBy ?? this.reviewedBy,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    submittedAt: submittedAt ?? this.submittedAt,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AccomplishmentReport) return false;
    return other.id == id &&
        other.workOrderId == workOrderId &&
        other.submittedBy == submittedBy &&
        other.completionNotes == completionNotes &&
        listEquals(other.photoUrls, photoUrls) &&
        listEquals(other.materialsUsed, materialsUsed) &&
        other.inventoryDeducted == inventoryDeducted &&
        other.reviewedBy == reviewedBy &&
        other.reviewedAt == reviewedAt &&
        other.submittedAt == submittedAt;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    workOrderId,
    submittedBy,
    completionNotes,
    ...photoUrls,
    ...materialsUsed,
    inventoryDeducted,
    reviewedBy,
    reviewedAt,
    submittedAt,
  ]);

  @override
  String toString() =>
      'AccomplishmentReport(id: $id, workOrderId: $workOrderId, '
      'materials: ${materialsUsed.length}, submittedAt: $submittedAt)';
}
