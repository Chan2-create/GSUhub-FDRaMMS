import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/utils/result.dart';
import '../../audit/presentation/current_actor_provider.dart';
import '../data/models/service_feedback.dart';

/// The rating of one report, live — null until its reporter rates it
/// (Objective 3.C). The detail page shows it once there.
final reportFeedbackProvider = StreamProvider.autoDispose
    .family<Result<ServiceFeedback?>, String>(
      (ref, reportId) =>
          ref.watch(feedbackRepositoryProvider).watchForReport(reportId),
    );

/// The three ratings of the service (manuscript §1.5, §1.7), in the order
/// the Ratings screen asks them.
enum RatingDimension {
  responseTime('Response time', 'How quickly GSU responded'),
  serviceQuality('Service quality', 'How well the work was done'),
  overallSatisfaction('Overall satisfaction', 'How satisfied you are overall');

  const RatingDimension(this.label, this.hint);

  final String label;
  final String hint;
}

@immutable
class RatingFormState {
  const RatingFormState({
    this.stars = const {},
    this.comments = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.submitted = false,
  });

  /// Stars given so far, per dimension.
  final Map<RatingDimension, int> stars;
  final String comments;
  final bool isSubmitting;
  final String? errorMessage;

  /// Set once the rating is saved, for the screen to leave.
  final bool submitted;

  int starsFor(RatingDimension dimension) => stars[dimension] ?? 0;

  /// All three are needed: each is its own judgement (§1.5), so none may be
  /// guessed from the others.
  bool get isComplete =>
      RatingDimension.values.every((dimension) => starsFor(dimension) > 0);

  RatingFormState copyWith({
    Map<RatingDimension, int>? stars,
    String? comments,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    bool? submitted,
  }) => RatingFormState(
    stars: stars ?? this.stars,
    comments: comments ?? this.comments,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    submitted: submitted ?? this.submitted,
  );
}

/// The Ratings screen's form for one report (Objective 3.C).
class RatingController extends Notifier<RatingFormState> {
  RatingController(this.reportId);

  final String reportId;

  /// The longest comment the screen takes; the rules allow no more.
  static const int commentLimit = 1000;

  @override
  RatingFormState build() => const RatingFormState();

  void setStars(RatingDimension dimension, int stars) {
    if (state.isSubmitting) return;
    state = state.copyWith(
      stars: {...state.stars, dimension: stars},
      clearError: true,
    );
  }

  void setComments(String comments) =>
      state = state.copyWith(comments: comments);

  Future<void> submit() async {
    if (state.isSubmitting || !state.isComplete) return;
    state = state.copyWith(isSubmitting: true, clearError: true);

    final rater = await ref.read(currentActorProvider.future);
    if (!ref.mounted) return;
    if (rater == null) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'You are signed out. Sign in again to rate.',
      );
      return;
    }

    final result = await ref
        .read(feedbackRepositoryProvider)
        .rate(
          reportId: reportId,
          rater: rater,
          responseTime: state.starsFor(RatingDimension.responseTime),
          serviceQuality: state.starsFor(RatingDimension.serviceQuality),
          overallSatisfaction: state.starsFor(
            RatingDimension.overallSatisfaction,
          ),
          comments: state.comments,
        );
    if (!ref.mounted) return;

    state = switch (result) {
      Success() => state.copyWith(isSubmitting: false, submitted: true),
      Error(:final failure) => state.copyWith(
        isSubmitting: false,
        errorMessage: failure.message,
      ),
    };
  }
}

final ratingControllerProvider = NotifierProvider.autoDispose
    .family<RatingController, RatingFormState, String>(RatingController.new);
