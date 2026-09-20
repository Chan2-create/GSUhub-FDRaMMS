import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/enums/report_status.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../audit/data/models/audit_log_entry.dart';
import '../../audit/presentation/current_actor_provider.dart';

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

  Future<Result<void>> _transition(
    String reportId,
    ReportStatus to, {
    String? reason,
  }) async {
    final actor = await _ref.read(currentActorProvider.future);
    if (actor == null) {
      return const Result.failure(
        PermissionFailure('Your session has expired. Please sign in again.'),
      );
    }

    final result = await _ref
        .read(damageReportRepositoryProvider)
        .transitionStatus(
          reportId: reportId,
          to: to,
          actor: actor,
          reason: reason,
        );

    if (result.isSuccess) {
      // The report itself is watched live; its audit trail is a one-shot
      // read, so it needs telling.
      _ref.invalidate(reportHistoryProvider(reportId));
    }
    return result;
  }
}

final reportReviewControllerProvider = Provider(ReportReviewController.new);
