import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/result.dart';
import '../models/damage_report.dart';
import 'damage_report_repository.dart';

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
  Stream<Result<List<DamageReport>>> watchByReporter(String reporterId) =>
      watchMany(
        query: collection(_path)
            .where('reporterId', isEqualTo: reporterId)
            .orderBy('submittedAt', descending: true),
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
  Future<Result<void>> setStatus(String reportId, ReportStatus status) =>
      updateDoc(
        path: _path,
        id: reportId,
        data: {'status': status.id, 'updatedAt': FirestoreRepository.serverNow},
      );

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
  }) => db.runBatch((batch) {
    for (final id in duplicateReportIds) {
      batch.update(collection(_path).doc(id), {
        'duplicateOf': parentReportId,
        'status': ReportStatus.merged.id,
        'reviewedBy': mergedBy,
        'reviewedAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      });
    }
    // Batched so a partial merge cannot happen: reports pointing at a
    // parent that was never marked reviewed would be invisible in both
    // the active queue and the merged set.
    batch.update(collection(_path).doc(parentReportId), {
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
