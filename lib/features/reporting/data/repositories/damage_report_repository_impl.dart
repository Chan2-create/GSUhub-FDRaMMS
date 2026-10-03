import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../models/damage_report.dart';
import '../models/report_submission.dart';
import '../models/status_change.dart';
import 'damage_report_repository.dart';
import 'status_history_writes.dart';

/// Firestore-backed [DamageReportRepository]. Persistence only — no
/// classification or scoring logic, which belongs to Objective 4.
class DamageReportRepositoryImpl extends FirestoreRepository
    implements DamageReportRepository {
  const DamageReportRepositoryImpl({required super.db, required super.guard});

  static const String _path = FirestorePaths.damageReports;

  @override
  Future<Result<DamageReport>> getById(String id) =>
      getOne(path: _path, id: id, convert: DamageReport.fromFirestore);

  @override
  Stream<Result<DamageReport>> watchById(String id) =>
      watchOne(path: _path, id: id, convert: DamageReport.fromFirestore);

  @override
  Stream<Result<List<StatusChange>>> watchStatusHistory(String reportId) =>
      watchMany(
        query: collection(_path)
            .doc(reportId)
            .collection(FirestorePaths.statusHistory)
            .orderBy('changedAt')
            // Far beyond any real report's history — even one sent back
            // for rework a few times has a dozen entries. A bound all the
            // same, so one malformed report cannot run up the reads.
            .limit(statusHistoryLimit),
        convert: StatusChange.fromFirestore,
      );

  static const int statusHistoryLimit = 50;

  /// Backed by the (reporterId, submittedAt desc) composite index. The
  /// limit is not optional: without it the rules refuse a requestor's query
  /// outright, which until 3.A left this unusable by the very people it was
  /// written for.
  @override
  Stream<Result<List<DamageReport>>> watchByReporter(String reporterId) =>
      watchMany(
        query: collection(_path)
            .where('reporterId', isEqualTo: reporterId)
            .orderBy('submittedAt', descending: true)
            .limit(DamageReportRepository.reporterQueryLimit),
        convert: DamageReport.fromFirestore,
      );

  @override
  Stream<Result<List<DamageReport>>> watchAll({
    ReportStatus? status,
    PriorityLevel? priority,
    String? categoryId,
    bool excludeDuplicates = true,
  }) {
    Query<Map<String, dynamic>> query = collection(_path);

    if (excludeDuplicates) {
      // Merged duplicates carry a duplicateOf pointer; the parent keeps
      // null. Filtering on null is how Firestore expresses "has not been
      // merged into anything".
      query = query.where('duplicateOf', isNull: true);
    }
    if (status != null) query = query.where('status', isEqualTo: status.id);
    if (priority != null) {
      query = query.where('officialPriority', isEqualTo: priority.id);
    }
    if (categoryId != null) {
      query = query.where('category', isEqualTo: categoryId);
    }

    return watchMany(
      query: query.orderBy('submittedAt', descending: true),
      convert: DamageReport.fromFirestore,
    );
  }

  @override
  Future<Result<String>> create(DamageReport report) =>
      add(path: _path, data: report.toFirestore());

  @override
  String newReportId() => collection(_path).doc().id;

  @override
  Future<Result<void>> submit({
    required String reportId,
    required ReportSubmission submission,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(_path).doc(reportId);

    // A transaction rather than a plain write because of the call guard's
    // retry: a write that times out may still have reached the server, and
    // its retry would then be an update, which the rules refuse a
    // requestor. Reading first turns that retry into a no-op. A
    // transaction also needs the server, so a report is never shown as
    // submitted while it is only queued on the phone.
    final existing = await transaction.get(reference);
    if (existing.exists) {
      if (existing.data()?['reporterId'] == submission.reporter.id) return;
      throw FirestoreRepository.precondition(
        'This report could not be filed. Please try again.',
      );
    }

    final now = DateTime.now().toUtc();
    final coordinates = submission.coordinates;

    // Built through the model so its validation and field names stay the
    // single definition, then stamped with server time.
    final report = DamageReport(
      id: reportId,
      reporterId: submission.reporter.id,
      reporterName: submission.reporter.name,
      title: submission.title.trim(),
      description: submission.description.trim(),
      requestorPriority: submission.requestorPriority,
      requestorCategory: submission.requestorCategory,
      status: ReportStatus.submitted,
      facilityId: submission.facilityId,
      facilityName: submission.facilityName,
      locationDescription: submission.locationDescription,
      assetId: submission.assetId,
      coordinates: coordinates == null
          ? null
          : GeoPoint(coordinates.latitude, coordinates.longitude),
      photoUrls: submission.photoUrls,
      submittedAt: now,
      updatedAt: now,
    );

    transaction.set(reference, {
      ...report.toFirestore(),
      'submittedAt': FirestoreRepository.serverNow,
      'updatedAt': FirestoreRepository.serverNow,
    });

    // The first timeline entry and the requestor's "Report received".
    stageReportMove(
      transaction,
      db.raw,
      reportId: reportId,
      reporterId: submission.reporter.id,
      reportTitle: report.title,
      to: ReportStatus.submitted,
      changedBy: submission.reporter.id,
    );

    stageAuditEntry(
      transaction,
      db.raw,
      actor: submission.reporter,
      action: AuditAction.created,
      entityType: FirestorePaths.damageReports,
      entityId: reportId,
      description: 'Submitted "${report.title}"',
      changes: {
        'facilityId': submission.facilityId,
        'photos': submission.photoUrls.length,
        'geoTagged': coordinates != null,
      },
    );
  });

  @override
  Future<Result<void>> update(DamageReport report) => updateDoc(
    path: _path,
    id: report.id,
    data: {...report.toFirestore(), 'updatedAt': FirestoreRepository.serverNow},
  );

  @override
  Future<Result<void>> setCategory({
    required String reportId,
    required String categoryId,
    required bool classifiedAutomatically,
    required String reviewedBy,
  }) => updateDoc(
    path: _path,
    id: reportId,
    data: {
      'category': categoryId,
      'classifiedAutomatically': classifiedAutomatically,
      'reviewedBy': reviewedBy,
      'reviewedAt': FirestoreRepository.serverNow,
      'updatedAt': FirestoreRepository.serverNow,
    },
  );

  @override
  Future<Result<void>> setOfficialPriority({
    required String reportId,
    required PriorityLevel priority,
    required String reviewedBy,
  }) => updateDoc(
    path: _path,
    id: reportId,
    data: {
      'officialPriority': priority.id,
      'reviewedBy': reviewedBy,
      'reviewedAt': FirestoreRepository.serverNow,
      'updatedAt': FirestoreRepository.serverNow,
    },
  );

  @override
  Future<Result<void>> setRecommendedPriority({
    required String reportId,
    required double priorityScore,
    required PriorityLevel recommendedPriority,
  }) => updateDoc(
    path: _path,
    id: reportId,
    data: {
      'priorityScore': priorityScore,
      'recommendedPriority': recommendedPriority.id,
      'updatedAt': FirestoreRepository.serverNow,
      // Deliberately does not touch officialPriority. The computed score
      // is decision support; only an Administrator sets the official
      // value (manuscript §1.2).
    },
  );

  @override
  Future<Result<void>> transitionStatus({
    required String reportId,
    required ReportStatus to,
    required AuditActor actor,
    String? reason,
  }) async {
    if (!reviewTargets.contains(to)) {
      return Result.failure(
        ValidationFailure(
          'A report moves to ${to.label} with its work order, not on its '
          'own.',
        ),
      );
    }

    final trimmedReason = reason?.trim() ?? '';
    if (to == ReportStatus.rejected && trimmedReason.isEmpty) {
      return const Result.failure(
        ValidationFailure('Give a reason for rejecting this report.'),
      );
    }

    return db.runTransaction<void>((transaction) async {
      final reference = collection(_path).doc(reportId);
      final snapshot = await transaction.get(reference);

      if (!snapshot.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'No damage report $reportId',
        );
      }

      // The stored status, not the caller's copy: a second administrator
      // may have acted on this report since the screen last refreshed.
      final stored = DamageReport.fromFirestore(snapshot);
      final current = stored.status;
      if (current == to) return;

      if (!current.canTransitionTo(to)) {
        throw FirebaseException(
          plugin: 'gsuhub',
          code: 'failed-precondition',
          message: 'A report cannot move from ${current.label} to ${to.label}.',
        );
      }

      final isDecision =
          to == ReportStatus.approved || to == ReportStatus.rejected;

      transaction.update(reference, {
        'status': to.id,
        'updatedAt': FirestoreRepository.serverNow,
        if (isDecision) 'reviewedBy': actor.id,
        if (isDecision) 'reviewedAt': FirestoreRepository.serverNow,
        if (to == ReportStatus.rejected) 'rejectionReason': trimmedReason,
      });

      stageReportMove(
        transaction,
        db.raw,
        reportId: reportId,
        reporterId: stored.reporterId,
        reportTitle: stored.title,
        to: to,
        from: current,
        changedBy: actor.id,
        note: to == ReportStatus.rejected ? trimmedReason : null,
      );

      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.statusChanged,
        entityType: FirestorePaths.damageReports,
        entityId: reportId,
        description: to == ReportStatus.rejected
            ? 'Rejected: $trimmedReason'
            : 'Status changed from ${current.label} to ${to.label}',
        changes: {
          'from': current.id,
          'to': to.id,
          if (to == ReportStatus.rejected) 'reason': trimmedReason,
        },
      );
    });
  }

  /// The statuses an administrator sets directly while reviewing. Every
  /// later stage is driven by the report's work order, so letting this
  /// method set `assigned` would create an assigned report with no work
  /// order behind it.
  static const Set<ReportStatus> reviewTargets = {
    ReportStatus.underReview,
    ReportStatus.approved,
    ReportStatus.rejected,
  };

  @override
  Future<Result<List<DamageReport>>> findPotentialDuplicates(
    String reportId,
  ) async {
    final source = await getById(reportId);

    return source.fold((report) async {
      // Candidate set is narrowed server-side by the cheap, indexable
      // criteria from §3.4 (same facility, same category). Description
      // similarity — the one criterion Firestore cannot evaluate — is
      // left to the caller in Objective 4, which owns the matching
      // algorithm and its threshold.
      if (report.facilityId == null) {
        return const Result<List<DamageReport>>.success([]);
      }

      Query<Map<String, dynamic>> query = collection(_path)
          .where('facilityId', isEqualTo: report.facilityId)
          .where('duplicateOf', isNull: true);

      if (report.category != null) {
        query = query.where('category', isEqualTo: report.category!.id);
      }

      final candidates = await getMany(
        query: query.orderBy('submittedAt', descending: true).limit(20),
        convert: DamageReport.fromFirestore,
      );

      return candidates.map(
        (list) => list.where((other) => other.id != reportId).toList(),
      );
    }, (failure) async => Result.failure(failure));
  }

  @override
  Future<Result<void>> mergeDuplicates({
    required String parentReportId,
    required List<String> duplicateReportIds,
    required String mergedBy,
  }) => db.runTransaction<void>((transaction) async {
    // One transaction so a partial merge cannot happen: reports pointing at
    // a parent that was never marked reviewed would be invisible in both
    // the active queue and the merged set. A transaction rather than a
    // batch so each report's history entry and notice commit with its
    // status, and so each duplicate can be read for who filed it — every
    // read before any write.
    final duplicates = <DamageReport>[];
    for (final id in duplicateReportIds) {
      final snapshot = await transaction.get(collection(_path).doc(id));
      if (!snapshot.exists) {
        throw FirestoreRepository.notFound('No damage report $id');
      }
      duplicates.add(DamageReport.fromFirestore(snapshot));
    }

    for (final duplicate in duplicates) {
      transaction.update(collection(_path).doc(duplicate.id), {
        'duplicateOf': parentReportId,
        'status': ReportStatus.merged.id,
        'reviewedBy': mergedBy,
        'reviewedAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      });
      stageReportMove(
        transaction,
        db.raw,
        reportId: duplicate.id,
        reporterId: duplicate.reporterId,
        reportTitle: duplicate.title,
        to: ReportStatus.merged,
        from: duplicate.status,
        changedBy: mergedBy,
        mergedInto: parentReportId,
      );
    }
    transaction.update(collection(_path).doc(parentReportId), {
      'updatedAt': FirestoreRepository.serverNow,
    });
  });

  @override
  Future<Result<void>> dismissDuplicateFlag(String reportId) => updateDoc(
    path: _path,
    id: reportId,
    data: {'duplicateOf': null, 'updatedAt': FirestoreRepository.serverNow},
  );
}
