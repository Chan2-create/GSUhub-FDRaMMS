import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/damage_report.dart';
import '../models/report_submission.dart';

/// Abstract contract for the `damage_reports` collection.
///
/// **Interface only** — implementation is 1.C.
abstract interface class DamageReportRepository {
  /// A fresh id for a report about to be submitted, reserved without
  /// writing anything — so its photo evidence can be uploaded under
  /// `damage_reports/{id}/` before the report itself exists, and the
  /// report can name its photos in the one write that creates it.
  String newReportId();

  /// Files a requestor's report as [reportId]: status `submitted`, stamped
  /// with server time, with an `audit_logs` entry in the same transaction
  /// (§3.4 Auditability names report submissions).
  ///
  /// Idempotent. When [reportId] already exists and is the same
  /// reporter's — an earlier attempt that reached the server even though
  /// the device timed out waiting — it succeeds without writing again.
  /// A retry must never file the same damage twice.
  Future<Result<void>> submit({
    required String reportId,
    required ReportSubmission submission,
  });

  Future<Result<DamageReport>> getById(String id);

  /// Live view of one report, backing the requestor's real-time status
  /// tracking (manuscript §1.5, "real-time status monitoring").
  Stream<Result<DamageReport>> watchById(String id);

  /// The most reports a requestor's own-report query returns, newest
  /// first. The rules refuse a requestor's list query without a limit at
  /// or below 100, so neither query below may go without one.
  static const int reporterQueryLimit = 100;

  /// A requestor's own submissions, newest first, read once — the home
  /// screen and My Reports (Objective 3.A). Live tracking is 3.B's, through
  /// [watchByReporter].
  Future<Result<List<DamageReport>>> getByReporter(String reporterId);

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

  /// Applies an administrator's review decision: Start review, Approve or
  /// Reject (Objective 2.B).
  ///
  /// Implementations must, in one transaction:
  /// - reject any move `ReportStatus.canTransitionTo` disallows, reading
  ///   the current status rather than trusting the caller's copy;
  /// - refuse targets outside the review stage — `assigned` onward moves
  ///   with the report's work order, never on its own;
  /// - require a non-blank [reason] when rejecting, and store it;
  /// - record the reviewer on approval or rejection;
  /// - append an `audit_logs` entry naming [actor].
  ///
  /// Replaces 1.B's `setStatus`, which wrote the status blindly.
  Future<Result<void>> transitionStatus({
    required String reportId,
    required ReportStatus to,
    required AuditActor actor,
    String? reason,
  });

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
