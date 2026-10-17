import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../../../reporting/data/models/damage_report.dart';
import '../../../reporting/data/repositories/status_history_writes.dart';
import '../models/service_feedback.dart';
import 'feedback_repository.dart';

/// Firestore-backed [FeedbackRepository]. Persistence only — no averaging
/// of the three ratings, which stay independent by design (§1.5).
/// Objective 1 moved this data to Supabase; the app uses [FeedbackRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreFeedbackRepository extends FirestoreRepository
    implements FeedbackRepository {
  const FirestoreFeedbackRepository({required super.db, required super.guard});

  static const String _path = FirestorePaths.feedback;

  @override
  Future<Result<ServiceFeedback>> getById(String id) =>
      getOne(path: _path, id: id, convert: ServiceFeedback.fromFirestore);

  @override
  Future<Result<ServiceFeedback?>> getByWorkOrder(String workOrderId) async {
    final matches = await getMany(
      query: collection(_path)
          .where('workOrderId', isEqualTo: workOrderId)
          .limit(1),
      convert: ServiceFeedback.fromFirestore,
    );

    // Absence is normal: rating is optional (Figure 23 offers "Skip"), so
    // this returns null rather than a NotFoundFailure.
    return matches.map((list) => list.isEmpty ? null : list.first);
  }

  @override
  Future<Result<List<ServiceFeedback>>> getByRequestor(String requestorId) =>
      getMany(
        query: collection(_path)
            .where('submittedBy', isEqualTo: requestorId)
            .orderBy('submittedAt', descending: true),
        convert: ServiceFeedback.fromFirestore,
      );

  @override
  Future<Result<List<ServiceFeedback>>> getInRange({
    required DateTime from,
    required DateTime to,
  }) => getMany(
    query: collection(_path)
        .where(
          'submittedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from.toUtc()),
        )
        .where(
          'submittedAt',
          isLessThanOrEqualTo: Timestamp.fromDate(to.toUtc()),
        )
        .orderBy('submittedAt', descending: true),
    convert: ServiceFeedback.fromFirestore,
  );

  @override
  Stream<Result<ServiceFeedback?>> watchForReport(String reportId) =>
      guard.stream(
        collection(_path)
            .doc(reportId)
            .snapshots()
            .map(
              (snapshot) => snapshot.exists
                  ? ServiceFeedback.fromFirestore(snapshot)
                  : null,
            ),
      );

  @override
  Future<Result<void>> rate({
    required String reportId,
    required AuditActor rater,
    required int responseTime,
    required int serviceQuality,
    required int overallSatisfaction,
    String? comments,
  }) => db.runTransaction<void>((transaction) async {
    final reportReference = collection(FirestorePaths.damageReports)
        .doc(reportId);
    final feedbackReference = collection(_path).doc(reportId);

    // Every read before any write, as transactions require.
    final reportSnapshot = await transaction.get(reportReference);
    final feedbackSnapshot = await transaction.get(feedbackReference);

    if (!reportSnapshot.exists) {
      throw FirestoreRepository.notFound('No damage report $reportId');
    }
    final report = DamageReport.fromFirestore(reportSnapshot);
    if (report.reporterId != rater.id) {
      throw FirestoreRepository.precondition(
        'Only the person who filed this report can rate the service.',
      );
    }

    // A retry of a rating that already reached the server: done. Read from
    // the stored documents, not the caller's copy, so a timed-out first
    // attempt is not mistaken for a second rating.
    if (feedbackSnapshot.exists) {
      if (feedbackSnapshot.data()?['submittedBy'] == rater.id &&
          report.status == ReportStatus.closed) {
        return;
      }
      throw FirestoreRepository.precondition(
        'This service has already been rated.',
      );
    }

    final workOrderId = report.workOrderId;
    if (report.status != ReportStatus.completed || workOrderId == null) {
      throw FirestoreRepository.precondition(
        'Only completed work can be rated. This report is '
        '${report.status.timelineLabel.toLowerCase()}.',
      );
    }

    final trimmed = comments?.trim() ?? '';
    // Built through the model so its validation (1–5 each) and field names
    // stay the single definition, then stamped with server time.
    final feedback = ServiceFeedback(
      id: reportId,
      workOrderId: workOrderId,
      reportId: reportId,
      submittedBy: rater.id,
      responseTimeRating: responseTime,
      serviceQualityRating: serviceQuality,
      overallSatisfactionRating: overallSatisfaction,
      comments: trimmed.isEmpty ? null : trimmed,
      submittedAt: DateTime.now().toUtc(),
    );

    transaction
      ..set(feedbackReference, {
        ...feedback.toFirestore(),
        'submittedAt': FirestoreRepository.serverNow,
      })
      ..update(reportReference, {
        'status': ReportStatus.closed.id,
        'updatedAt': FirestoreRepository.serverNow,
      });

    stageReportMove(
      transaction,
      db.raw,
      reportId: reportId,
      reporterId: report.reporterId,
      reportTitle: report.title,
      to: ReportStatus.closed,
      from: ReportStatus.completed,
      changedBy: rater.id,
    );
    stageAuditEntry(
      transaction,
      db.raw,
      actor: rater,
      action: AuditAction.statusChanged,
      entityType: FirestorePaths.damageReports,
      entityId: reportId,
      description: 'Rated the service and closed the report',
      changes: {
        'from': ReportStatus.completed.id,
        'to': ReportStatus.closed.id,
        'feedbackId': reportId,
      },
    );
  });
}
