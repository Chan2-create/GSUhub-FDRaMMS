import '../../../../core/data/data_record.dart';
import '../../../../core/utils/record_converters.dart';

/// A `feedback` document — the requestor's post-service evaluation
/// (manuscript §1.7 "Feedback and Rating System").
///
/// Carries **three independent ratings, not one blended score**. §1.5
/// specifies "post-service feedback and rating based on response time,
/// service quality, and overall satisfaction", and §1.7 repeats the three
/// dimensions. Averaging them here would destroy exactly the signal the
/// GSU wants — a fast but sloppy repair and a slow but excellent one are
/// different problems, and a single number cannot tell them apart.
///
/// Named `ServiceFeedback` rather than `Feedback` to avoid colliding with
/// Flutter's `Feedback` class from `package:flutter/material.dart`.
class ServiceFeedback {
  ServiceFeedback({
    required this.id,
    required this.workOrderId,
    required this.reportId,
    required this.submittedBy,
    required this.responseTimeRating,
    required this.serviceQualityRating,
    required this.overallSatisfactionRating,
    required this.submittedAt,
    this.comments,
  }) {
    RecordConverters.validateNotBlank(workOrderId, 'workOrderId');
    RecordConverters.validateNotBlank(reportId, 'reportId');
    RecordConverters.validateNotBlank(submittedBy, 'submittedBy');
    RecordConverters.validateRange(
      responseTimeRating,
      minRating,
      maxRating,
      'responseTimeRating',
    );
    RecordConverters.validateRange(
      serviceQualityRating,
      minRating,
      maxRating,
      'serviceQualityRating',
    );
    RecordConverters.validateRange(
      overallSatisfactionRating,
      minRating,
      maxRating,
      'overallSatisfactionRating',
    );
  }

  factory ServiceFeedback.fromRecord(DataRecord record) {
    final data = record.fields;
    return ServiceFeedback(
      id: record.id,
      workOrderId: RecordConverters.require<String>(data, 'workOrderId'),
      reportId: RecordConverters.require<String>(data, 'reportId'),
      submittedBy: RecordConverters.require<String>(data, 'submittedBy'),
      responseTimeRating: RecordConverters.require<int>(
        data,
        'responseTimeRating',
      ),
      serviceQualityRating: RecordConverters.require<int>(
        data,
        'serviceQualityRating',
      ),
      overallSatisfactionRating: RecordConverters.require<int>(
        data,
        'overallSatisfactionRating',
      ),
      comments: RecordConverters.optional<String>(data, 'comments'),
      submittedAt: RecordConverters.requireDate(data, 'submittedAt'),
    );
  }

  /// Rating floor. The five-star control in the mobile rating screen
  /// (manuscript Figure 23) sets the 1–5 scale.
  static const int minRating = 1;

  /// Rating ceiling — five stars.
  static const int maxRating = 5;

  final String id;

  /// The completed work order being rated.
  final String workOrderId;

  /// The originating report, so feedback can be shown on the requestor's
  /// own report history without traversing the work order.
  final String reportId;

  final String submittedBy;

  /// How promptly GSU responded.
  final int responseTimeRating;

  /// How well the repair itself was done.
  final int serviceQualityRating;

  /// Overall satisfaction — a distinct judgement, not a computed average
  /// of the other two.
  final int overallSatisfactionRating;

  /// Free-text remarks (Figure 23, "Share your feedback...").
  final String? comments;

  final DateTime submittedAt;

  Map<String, dynamic> toFields() => {
    'workOrderId': workOrderId,
    'reportId': reportId,
    'submittedBy': submittedBy,
    'responseTimeRating': responseTimeRating,
    'serviceQualityRating': serviceQualityRating,
    'overallSatisfactionRating': overallSatisfactionRating,
    'comments': comments,
    'submittedAt': submittedAt,
  };

  ServiceFeedback copyWith({
    String? id,
    String? workOrderId,
    String? reportId,
    String? submittedBy,
    int? responseTimeRating,
    int? serviceQualityRating,
    int? overallSatisfactionRating,
    String? comments,
    DateTime? submittedAt,
  }) => ServiceFeedback(
    id: id ?? this.id,
    workOrderId: workOrderId ?? this.workOrderId,
    reportId: reportId ?? this.reportId,
    submittedBy: submittedBy ?? this.submittedBy,
    responseTimeRating: responseTimeRating ?? this.responseTimeRating,
    serviceQualityRating: serviceQualityRating ?? this.serviceQualityRating,
    overallSatisfactionRating:
        overallSatisfactionRating ?? this.overallSatisfactionRating,
    comments: comments ?? this.comments,
    submittedAt: submittedAt ?? this.submittedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceFeedback &&
          other.id == id &&
          other.workOrderId == workOrderId &&
          other.reportId == reportId &&
          other.submittedBy == submittedBy &&
          other.responseTimeRating == responseTimeRating &&
          other.serviceQualityRating == serviceQualityRating &&
          other.overallSatisfactionRating == overallSatisfactionRating &&
          other.comments == comments &&
          other.submittedAt == submittedAt;

  @override
  int get hashCode => Object.hash(
    id,
    workOrderId,
    reportId,
    submittedBy,
    responseTimeRating,
    serviceQualityRating,
    overallSatisfactionRating,
    comments,
    submittedAt,
  );

  @override
  String toString() =>
      'ServiceFeedback(id: $id, workOrderId: $workOrderId, '
      'responseTime: $responseTimeRating, quality: $serviceQualityRating, '
      'overall: $overallSatisfactionRating)';
}
