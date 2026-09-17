import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../models/service_feedback.dart';
import 'feedback_repository.dart';

/// Firestore-backed [FeedbackRepository]. Persistence only — no averaging
/// of the three ratings, which stay independent by design (§1.5).
class FeedbackRepositoryImpl extends FirestoreRepository
    implements FeedbackRepository {
  const FeedbackRepositoryImpl({required super.db, required super.guard});

  static const String _path = FirestorePaths.feedback;

  @override
  Future<Result<ServiceFeedback>> getById(String id) =>
      getOne(path: _path, id: id, convert: ServiceFeedback.fromFirestore);

  @override
  Future<Result<ServiceFeedback?>> getByWorkOrder(String workOrderId) async {
    final matches = await getMany(
      query: collection(_path)
          .where('workOrderId', isEqualTo: workOrderId)
          .limit(1),
      convert: ServiceFeedback.fromFirestore,
    );

    // Absence is normal: rating is optional (Figure 23 offers "Skip"), so
    // this returns null rather than a NotFoundFailure.
    return matches.map((list) => list.isEmpty ? null : list.first);
  }

  @override
  Future<Result<List<ServiceFeedback>>> getByRequestor(String requestorId) =>
      getMany(
        query: collection(_path)
            .where('submittedBy', isEqualTo: requestorId)
            .orderBy('submittedAt', descending: true),
        convert: ServiceFeedback.fromFirestore,
      );

  @override
  Future<Result<List<ServiceFeedback>>> getInRange({
    required DateTime from,
    required DateTime to,
  }) => getMany(
    query: collection(_path)
        .where(
          'submittedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from.toUtc()),
        )
        .where(
          'submittedAt',
          isLessThanOrEqualTo: Timestamp.fromDate(to.toUtc()),
        )
        .orderBy('submittedAt', descending: true),
    convert: ServiceFeedback.fromFirestore,
  );

  @override
  Future<Result<String>> submit(ServiceFeedback feedback) async {
    // One rating per work order. Checked here rather than relying on the
    // UI hiding the button, because a stale screen or a back-navigation
    // would otherwise let a second rating through and skew the averages
    // the Admin analytics view will compute.
    final existing = await getByWorkOrder(feedback.workOrderId);

    return existing.fold((found) async {
      if (found != null) {
        return const Result<String>.failure(
          ValidationFailure(
            'Feedback has already been submitted for this work order.',
          ),
        );
      }
      return add(path: _path, data: feedback.toFirestore());
    }, (failure) async => Result.failure(failure));
  }
}
