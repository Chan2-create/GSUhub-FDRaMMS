import 'package:flutter/foundation.dart';

import '../../../core/constants/damage_categories.dart';
import '../../../core/enums/priority_level.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../reporting/data/models/report_assessment.dart';
import '../data/models/prioritization_config.dart';
import '../domain/priority_scorer.dart';

/// What an administrator has entered so far in a report's review panel
/// (Objectives 4.A–4.C), before it is saved.
///
/// Holds only what was saved before or picked since. The Frequency hint is
/// not stored here: it is a default the panel offers — [ratingsWith] — until
/// the administrator picks a Frequency of their own.
@immutable
class AssessmentDraft {
  const AssessmentDraft({
    this.category,
    this.ratings = const {},
    this.officialPriority,
    this.officialChosen = false,
  });

  /// Starts from what [report] already carries: a saved assessment, or the
  /// keyword classifier's category — the one stored when it was filed, or
  /// else [suggestion], the dictionary's match today.
  factory AssessmentDraft.of(
    DamageReport report, {
    DamageCategory? suggestion,
  }) => AssessmentDraft(
    category: report.category ?? suggestion,
    ratings: {
      PrioritizationCriterion.severity: ?report.severityRating,
      PrioritizationCriterion.safetyRisk: ?report.safetyRiskRating,
      PrioritizationCriterion.frequency: ?report.frequencyRating,
      PrioritizationCriterion.locationImportance:
          ?report.locationImportanceRating,
    },
    officialPriority: report.officialPriority,
    officialChosen: report.officialPriority != null,
  );

  final DamageCategory? category;

  /// The ratings saved before, or picked since.
  final Map<PrioritizationCriterion, int> ratings;

  final PriorityLevel? officialPriority;

  /// The official level was saved before or picked by the administrator,
  /// so it no longer follows the recommendation as the ratings change. A
  /// saved decision is never changed behind the administrator's back.
  final bool officialChosen;

  AssessmentDraft withCategory(DamageCategory category) =>
      _copy(category: category);

  AssessmentDraft withRating(PrioritizationCriterion criterion, int rating) =>
      _copy(ratings: {...ratings, criterion: rating});

  AssessmentDraft withOfficial(PriorityLevel level) =>
      _copy(officialPriority: level, officialChosen: true);

  /// [ratings], with [frequencyHint] standing in for a Frequency not yet
  /// picked.
  Map<PrioritizationCriterion, int> ratingsWith(int? frequencyHint) => {
    PrioritizationCriterion.frequency: ?frequencyHint,
    ...ratings,
  };

  /// The official level the panel shows selected: the one chosen, or else
  /// the [recommended] one — the manuscript's "confirm" (§1.5).
  PriorityLevel? officialFor(PriorityLevel? recommended) =>
      officialChosen ? officialPriority : recommended;

  /// The assessment to save, or null while anything is missing.
  ///
  /// [suggestion] is the keyword classifier's category, and [report] the
  /// report as stored: the category stays marked automatic when the
  /// administrator confirms the classifier's choice, and becomes theirs when
  /// they pick another.
  ReportAssessment? toAssessment({
    required DamageReport report,
    required PriorityScorer scorer,
    required DamageCategory? suggestion,
    int? frequencyHint,
  }) {
    final chosen = category;
    if (chosen == null) return null;
    final all = ratingsWith(frequencyHint);
    final score = scorer.score(all);
    if (score == null) return null;
    final recommended = scorer.levelFor(score);
    final official = officialFor(recommended);
    if (official == null) return null;

    final automatic =
        chosen == suggestion ||
        (chosen == report.category && report.classifiedAutomatically);
    return ReportAssessment(
      category: chosen,
      classifiedAutomatically: automatic,
      severityRating: all[PrioritizationCriterion.severity]!,
      safetyRiskRating: all[PrioritizationCriterion.safetyRisk]!,
      frequencyRating: all[PrioritizationCriterion.frequency]!,
      locationImportanceRating:
          all[PrioritizationCriterion.locationImportance]!,
      priorityScore: score,
      recommendedPriority: recommended,
      officialPriority: official,
    );
  }

  AssessmentDraft _copy({
    DamageCategory? category,
    Map<PrioritizationCriterion, int>? ratings,
    PriorityLevel? officialPriority,
    bool? officialChosen,
  }) => AssessmentDraft(
    category: category ?? this.category,
    ratings: ratings ?? this.ratings,
    officialPriority: officialPriority ?? this.officialPriority,
    officialChosen: officialChosen ?? this.officialChosen,
  );

  @override
  bool operator ==(Object other) =>
      other is AssessmentDraft &&
      other.category == category &&
      mapEquals(other.ratings, ratings) &&
      other.officialPriority == officialPriority &&
      other.officialChosen == officialChosen;

  @override
  int get hashCode => Object.hash(
    category,
    Object.hashAll(ratings.entries.map((e) => '${e.key.id}:${e.value}')),
    officialPriority,
    officialChosen,
  );
}
