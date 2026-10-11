import 'dart:async';

import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/feedback/data/models/service_feedback.dart';
import 'package:gsuhub/features/feedback/data/repositories/feedback_repository.dart';

/// Ratings in memory, live (Objective 3.C). [rate] files one and calls
/// [onRated], which the harness uses to close the report as the real
/// transaction does.
class FakeFeedbackRepository implements FeedbackRepository {
  FakeFeedbackRepository({this.onRated});

  void Function(String reportId)? onRated;

  final _ratings = <String, ServiceFeedback>{};
  final _changes = StreamController<void>.broadcast();

  /// When set, [rate] fails with this instead of filing anything.
  Failure? rateFailure;

  /// Completes [rate] only when the test says so, to see it in progress.
  Completer<void>? holdRate;

  final rated = <({String reportId, String raterId, String? comments})>[];

  /// Files a rating directly, as if given earlier.
  void put(ServiceFeedback feedback) {
    _ratings[feedback.reportId] = feedback;
    _changes.add(null);
  }

  @override
  Stream<Result<ServiceFeedback?>> watchForReport(String reportId) =>
      Stream.multi((listener) {
        listener.add(Result.success(_ratings[reportId]));
        final changes = _changes.stream.listen(
          (_) => listener.add(Result.success(_ratings[reportId])),
        );
        listener.onCancel = changes.cancel;
      });

  @override
  Future<Result<void>> rate({
    required String reportId,
    required AuditActor rater,
    required int responseTime,
    required int serviceQuality,
    required int overallSatisfaction,
    String? comments,
  }) async {
    await holdRate?.future;
    if (rateFailure case final failure?) return Result.failure(failure);
    final trimmed = comments?.trim() ?? '';
    rated.add((
      reportId: reportId,
      raterId: rater.id,
      comments: trimmed.isEmpty ? null : trimmed,
    ));
    put(
      ServiceFeedback(
        id: reportId,
        workOrderId: 'wo-$reportId',
        reportId: reportId,
        submittedBy: rater.id,
        responseTimeRating: responseTime,
        serviceQualityRating: serviceQuality,
        overallSatisfactionRating: overallSatisfaction,
        comments: trimmed.isEmpty ? null : trimmed,
        submittedAt: DateTime.now().toUtc(),
      ),
    );
    onRated?.call(reportId);
    return const Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Future<void> dispose() => _changes.close();
}
