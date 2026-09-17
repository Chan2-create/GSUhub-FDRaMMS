import '../../../../core/utils/result.dart';
import '../models/service_feedback.dart';

/// Abstract contract for the `feedback` collection (manuscript §1.7
/// "Feedback and Rating System").
///
/// **Interface only** — implementation is 1.C.
abstract interface class FeedbackRepository {
  Future<Result<ServiceFeedback>> getById(String id);

  /// Feedback for one completed work order, if the requestor left any.
  /// §1.5 makes rating optional (Figure 23 offers a "Skip" action), so an
  /// absent result is a normal outcome.
  Future<Result<ServiceFeedback?>> getByWorkOrder(String workOrderId);

  /// A requestor's own submitted feedback.
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

  /// Submits post-service feedback. One submission per work order —
  /// implementations reject a second.
  Future<Result<String>> submit(ServiceFeedback feedback);
}
