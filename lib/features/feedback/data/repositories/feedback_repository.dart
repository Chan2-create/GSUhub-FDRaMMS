import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/service_feedback.dart';

/// Abstract contract for the `feedback` collection (manuscript §1.7
/// "Feedback and Rating System").
///
/// A rating is filed under its report's id: one per report, by the person
/// who filed it (Objective 3.C).
abstract interface class FeedbackRepository {
  Future<Result<ServiceFeedback>> getById(String id);

  /// Feedback for one completed work order, if the requestor left any.
  /// §1.5 makes rating optional (Figure 23 offers a "Skip" action), so an
  /// absent result is a normal outcome. Administrators only — the rules
  /// let nobody else list feedback.
  Future<Result<ServiceFeedback?>> getByWorkOrder(String workOrderId);

  /// A requestor's submitted feedback. Administrators only, as above.
  Future<Result<List<ServiceFeedback>>> getByRequestor(String requestorId);

  /// All feedback in a date range, for the Admin analytics view.
  ///
  /// Returns the raw records rather than an aggregate: the three ratings
  /// are independent by design (§1.5), and any averaging is a presentation
  /// decision for the caller, not something to bake in here.
  Future<Result<List<ServiceFeedback>>> getInRange({
    required DateTime from,
    required DateTime to,
  });

  /// The rating of one report, live — null until its reporter rates it
  /// (Objective 3.C).
  Stream<Result<ServiceFeedback?>> watchForReport(String reportId);

  /// Files [rater]'s rating of their completed report [reportId] and closes
  /// the report (Objective 3.C), in one transaction: the `feedback`
  /// document, the report's move from `completed` to `closed`, its
  /// `status_history` entry and an `audit_logs` entry.
  ///
  /// Refuses a report that is not [rater]'s, not completed, or already
  /// rated. Idempotent: a retry of a rating that already reached the
  /// server succeeds without writing again.
  ///
  /// The three ratings stay separate (§1.5); [comments] is optional and
  /// trimmed, blank meaning none.
  Future<Result<void>> rate({
    required String reportId,
    required AuditActor rater,
    required int responseTime,
    required int serviceQuality,
    required int overallSatisfaction,
    String? comments,
  });
}
