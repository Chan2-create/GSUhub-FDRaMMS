import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/enums/report_status.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../audit/data/models/audit_actor.dart';
import '../../audit/data/models/audit_log_entry.dart';
import '../../audit/presentation/current_actor_provider.dart';
import '../data/models/report_assessment.dart';

/// The recorded history of one report, for the detail view's timeline.
final reportHistoryProvider =
    FutureProvider.family<Result<List<AuditLogEntry>>, String>(
      (ref, reportId) => ref
          .watch(auditLogRepositoryProvider)
          .getForEntity(entityType: 'damage_reports', entityId: reportId),
    );

/// Applies the administrator's review decisions.
///
/// Thin on purpose: the rules — which moves are legal, that a rejection
/// needs a reason, that every move is audited — live in the repository,
/// where a second caller cannot skip them. This resolves who is acting and
/// refreshes the history afterwards.
class ReportReviewController {
  const ReportReviewController(this._ref);

  final Ref _ref;

  Future<Result<void>> startReview(String reportId) =>
      _transition(reportId, ReportStatus.underReview);

  Future<Result<void>> approve(String reportId) =>
      _transition(reportId, ReportStatus.approved);

  Future<Result<void>> reject(String reportId, String reason) =>
      _transition(reportId, ReportStatus.rejected, reason: reason);

  /// Saves the administrator's classification and priority (Objectives
  /// 4.A–4.C).
  Future<Result<void>> recordAssessment(
    String reportId,
    ReportAssessment assessment,
  ) => _act(
    [reportId],
    (actor) => _ref
        .read(damageReportRepositoryProvider)
        .recordAssessment(
          reportId: reportId,
          assessment: assessment,
          actor: actor,
        ),
  );

  /// Closes [duplicateId] as a duplicate of [parentId] (Objective 4.C).
  Future<Result<void>> merge({
    required String parentId,
    required String duplicateId,
  }) => _act(
    [parentId, duplicateId],
    (actor) => _ref
        .read(damageReportRepositoryProvider)
        .mergeDuplicates(
          parentReportId: parentId,
          duplicateReportIds: [duplicateId],
          actor: actor,
        ),
  );

  /// Records that the two reports are separate requests, not duplicates
  /// (Objective 4.C).
  Future<Result<void>> keepSeparate(String reportId, String otherReportId) =>
      _act(
        [reportId, otherReportId],
        (actor) => _ref
            .read(damageReportRepositoryProvider)
            .keepSeparate(
              reportId: reportId,
              otherReportId: otherReportId,
              actor: actor,
            ),
      );

  Future<Result<void>> _transition(
    String reportId,
    ReportStatus to, {
    String? reason,
  }) => _act(
    [reportId],
    (actor) => _ref
        .read(damageReportRepositoryProvider)
        .transitionStatus(
          reportId: reportId,
          to: to,
          actor: actor,
          reason: reason,
        ),
  );

  /// Runs [action] as the signed-in administrator, then refreshes the
  /// history of every report it touched.
  Future<Result<void>> _act(
    List<String> reportIds,
    Future<Result<void>> Function(AuditActor actor) action,
  ) async {
    final actor = await _ref.read(currentActorProvider.future);
    if (actor == null) {
      return const Result.failure(
        PermissionFailure('Your session has expired. Please sign in again.'),
      );
    }

    final result = await action(actor);
    if (result.isSuccess) {
      // The reports themselves are watched live; their audit trails are
      // one-shot reads, so they need telling.
      for (final id in reportIds) {
        _ref.invalidate(reportHistoryProvider(id));
      }
    }
    return result;
  }
}

final reportReviewControllerProvider = Provider(ReportReviewController.new);
