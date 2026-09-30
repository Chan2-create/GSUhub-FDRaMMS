import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../audit/presentation/current_actor_provider.dart';

/// The report an administrator has picked to assign, if any.
///
/// Assignment takes two choices — which report, then who — so the screen
/// holds the first while the second is made. Null means "pick a report
/// first", which is why the personnel Assign buttons are disabled.
class SelectedReportController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? reportId) => state = reportId;
}

final selectedReportProvider =
    NotifierProvider<SelectedReportController, String?>(
      SelectedReportController.new,
    );

/// Creates the work order and everything that goes with it.
///
/// One repository call: the transaction there raises the work order, moves
/// the report to ASSIGNED, counts the job against the person and writes
/// the audit entries, or does none of it.
class AssignmentController {
  const AssignmentController(this._ref);

  final Ref _ref;

  Future<Result<String>> assign({
    required String reportId,
    required String personnelId,
    DateTime? targetCompletion,
  }) async {
    final actor = await _ref.read(currentActorProvider.future);
    if (actor == null) {
      return const Result.failure(
        PermissionFailure('Your session has expired. Please sign in again.'),
      );
    }

    final result = await _ref
        .read(workOrderRepositoryProvider)
        .assignFromReport(
          reportId: reportId,
          personnelId: personnelId,
          actor: actor,
          scheduledFor: targetCompletion,
        );

    if (result.isSuccess) {
      // Both lists are live streams and update themselves; the selection
      // is what needs clearing, so the queue does not keep pointing at a
      // report that has just left it.
      _ref.read(selectedReportProvider.notifier).select(null);
    }
    return result;
  }
}

final assignmentControllerProvider = Provider(AssignmentController.new);
