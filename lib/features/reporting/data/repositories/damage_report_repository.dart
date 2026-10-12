import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/damage_report.dart';
import '../models/report_assessment.dart';
import '../models/report_submission.dart';
import '../models/status_change.dart';

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
  /// with server time, with the first `status_history` entry and an
  /// `audit_logs` entry in the same transaction (§3.4 Auditability names
  /// report submissions).
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

  /// Live view of one report's status history, oldest first: the
  /// requestor's progress timeline (Objective 3.B). Every method here that
  /// moves a report writes its entry in the same transaction.
  Stream<Result<List<StatusChange>>> watchStatusHistory(String reportId);

  /// The most reports a requestor's own-report query returns, newest
  /// first. The rules refuse a requestor's list query without a limit at
  /// or below 100, so the query may not go without one.
  static const int reporterQueryLimit = 100;

  /// A requestor's own submissions, newest first, live — the home screen
  /// and My Reports (Objectives 3.A and 3.B).
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

  /// Records an administrator's review of [reportId]'s classification and
  /// priority (Objectives 4.A–4.C): the damage type, the four criterion
  /// ratings, the score and recommended level they give, and the official
  /// priority — the act the manuscript requires "before work-order
  /// assignment" (§1.5).
  ///
  /// Implementations must, in one transaction:
  /// - read the stored report, and refuse one that is merged, already has a
  ///   work order, or is past review (only `submitted`, `underReview` and
  ///   `approved` reports are assessed);
  /// - write the assessment and record the reviewer;
  /// - append an `audit_logs` entry naming [actor], saying whether the
  ///   official priority confirms or modifies the recommendation.
  ///
  /// Replaces 1.B's `setCategory`, `setOfficialPriority` and
  /// `setRecommendedPriority`, which wrote one field each with no audit
  /// entry — and so could leave an official priority with no ratings
  /// behind it.
  Future<Result<void>> recordAssessment({
    required String reportId,
    required ReportAssessment assessment,
    required AuditActor actor,
  });

  /// How many reports of [category] at [facilityId] were filed since
  /// [since], merged duplicates included — the Frequency hint
  /// (Objective 4.B). Administrators only: the rules let a requestor list
  /// nothing but their own reports.
  Future<Result<int>> countSimilarReports({
    required String facilityId,
    required DamageCategory category,
    required DateTime since,
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
  /// - append a `status_history` entry, carrying the rejection reason;
  /// - append an `audit_logs` entry naming [actor].
  ///
  /// Replaces 1.B's `setStatus`, which wrote the status blindly.
  Future<Result<void>> transitionStatus({
    required String reportId,
    required ReportStatus to,
    required AuditActor actor,
    String? reason,
  });

  /// Closes [duplicateReportIds] as duplicates of [parentReportId]
  /// (§3.4; Objective 4.C). The merged reports keep their own documents and
  /// ids; they gain a `duplicateOf` pointer, a `status_history` entry and
  /// their reporter's notice, and an `audit_logs` entry naming [actor].
  ///
  /// In one transaction, refusing — and writing nothing — when the parent
  /// is missing, closed or itself merged, or when a duplicate is the
  /// parent, missing, or no longer awaiting review (only a `submitted` or
  /// `underReview` report with no work order can be merged).
  ///
  /// Which reports are duplicates is the administrator's call: detection
  /// (`DuplicateDetector`) only flags them.
  Future<Result<void>> mergeDuplicates({
    required String parentReportId,
    required List<String> duplicateReportIds,
    required AuditActor actor,
  });

  /// Records that [reportId] and [otherReportId] are separate requests,
  /// not duplicates — §3.4's "dismiss duplicate flags, or retain reports as
  /// separate maintenance requests" (Objective 4.C) — so the pair is never
  /// flagged again. Kept on both reports, with an `audit_logs` entry.
  ///
  /// Replaces 1.B's `dismissDuplicateFlag`, which cleared the merge
  /// pointer: flags are computed, not stored, so there was no flag to
  /// clear.
  Future<Result<void>> keepSeparate({
    required String reportId,
    required String otherReportId,
    required AuditActor actor,
  });
}
