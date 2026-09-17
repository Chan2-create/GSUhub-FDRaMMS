import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/result.dart';
import '../models/damage_report.dart';

/// Abstract contract for the `damage_reports` collection.
///
/// **Interface only** — implementation is 1.C.
abstract interface class DamageReportRepository {
  Future<Result<DamageReport>> getById(String id);

  /// Live view of one report, backing the requestor's real-time status
  /// tracking (manuscript §1.5, "real-time status monitoring").
  Stream<Result<DamageReport>> watchById(String id);

  /// A requestor's own submissions, for "My Reports" (Figure 22).
  Stream<Result<List<DamageReport>>> watchByReporter(String reporterId);

  /// Admin queue, filtered. Backs the Damage Reports table and its filter
  /// bar (Figure 16). [excludeDuplicates] hides reports merged into a
  /// parent so they don't clutter the active queue.
  Stream<Result<List<DamageReport>>> watchAll({
    ReportStatus? status,
    PriorityLevel? priority,
    String? categoryId,
    bool excludeDuplicates = true,
  });

  Future<Result<String>> create(DamageReport report);

  Future<Result<void>> update(DamageReport report);

  /// Records the Administrator's classification decision.
  Future<Result<void>> setCategory({
    required String reportId,
    required String categoryId,
    required bool classifiedAutomatically,
    required String reviewedBy,
  });

  /// Records the Administrator's official priority, the only
  /// authoritative one (§1.2). Distinct from [update] because it is the
  /// specific act the manuscript requires before work-order assignment,
  /// and must be audited as such.
  Future<Result<void>> setOfficialPriority({
    required String reportId,
    required PriorityLevel priority,
    required String reviewedBy,
  });

  /// Stores the computed weighted score and the level it maps to.
  /// Decision support only — never sets the official priority.
  Future<Result<void>> setRecommendedPriority({
    required String reportId,
    required double priorityScore,
    required PriorityLevel recommendedPriority,
  });

  Future<Result<void>> setStatus(String reportId, ReportStatus status);

  /// Candidate duplicates of [reportId], per the `config/duplicate_detection`
  /// criteria. Flagging only — §1.5 requires administrator verification
  /// before anything is merged.
  Future<Result<List<DamageReport>>> findPotentialDuplicates(String reportId);

  /// Marks [duplicateReportIds] as duplicates of [parentReportId]. The
  /// merged reports keep their own documents and ids; they gain a
  /// `duplicateOf` pointer (§3.4).
  Future<Result<void>> mergeDuplicates({
    required String parentReportId,
    required List<String> duplicateReportIds,
    required String mergedBy,
  });

  /// Clears a duplicate flag, retaining the report as a separate request
  /// (§3.4's "dismiss" / "retain" options).
  Future<Result<void>> dismissDuplicateFlag(String reportId);
}
