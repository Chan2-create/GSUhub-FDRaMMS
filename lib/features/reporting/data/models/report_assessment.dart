import 'package:flutter/foundation.dart';

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/utils/firestore_converters.dart';

/// An administrator's review of one report's classification and priority
/// (Objectives 4.A–4.C): the damage type they confirm or choose, the four
/// criterion ratings, the score and recommended level the weighted formula
/// gives, and the official priority they set.
///
/// Saved in one write, so a report never carries an official priority
/// without the ratings behind it, or ratings without the score they give.
@immutable
class ReportAssessment {
  ReportAssessment({
    required this.category,
    required this.classifiedAutomatically,
    required this.severityRating,
    required this.safetyRiskRating,
    required this.frequencyRating,
    required this.locationImportanceRating,
    required this.priorityScore,
    required this.recommendedPriority,
    required this.officialPriority,
  }) {
    for (final (field, rating) in [
      ('severityRating', severityRating),
      ('safetyRiskRating', safetyRiskRating),
      ('frequencyRating', frequencyRating),
      ('locationImportanceRating', locationImportanceRating),
    ]) {
      FirestoreConverters.validateRange(rating, 1, 4, field);
    }
    FirestoreConverters.validateRange(priorityScore, 1.0, 4.0, 'priorityScore');
  }

  final DamageCategory category;

  /// The category is the keyword classifier's (4.A), confirmed rather than
  /// chosen by hand.
  final bool classifiedAutomatically;

  final int severityRating;
  final int safetyRiskRating;
  final int frequencyRating;
  final int locationImportanceRating;

  /// The weighted score of the four ratings (4.B).
  final double priorityScore;

  /// The level [priorityScore] falls in (Table 3.5) — decision support.
  final PriorityLevel recommendedPriority;

  /// The level the administrator set — the only authoritative one (§1.2).
  final PriorityLevel officialPriority;

  /// Whether the administrator set a different level from the one
  /// recommended.
  bool get modifiesRecommendation => officialPriority != recommendedPriority;

  @override
  bool operator ==(Object other) =>
      other is ReportAssessment &&
      other.category == category &&
      other.classifiedAutomatically == classifiedAutomatically &&
      other.severityRating == severityRating &&
      other.safetyRiskRating == safetyRiskRating &&
      other.frequencyRating == frequencyRating &&
      other.locationImportanceRating == locationImportanceRating &&
      other.priorityScore == priorityScore &&
      other.recommendedPriority == recommendedPriority &&
      other.officialPriority == officialPriority;

  @override
  int get hashCode => Object.hash(
    category,
    classifiedAutomatically,
    severityRating,
    safetyRiskRating,
    frequencyRating,
    locationImportanceRating,
    priorityScore,
    recommendedPriority,
    officialPriority,
  );

  @override
  String toString() =>
      'ReportAssessment(${category.id}, score: $priorityScore, '
      'recommended: ${recommendedPriority.id}, '
      'official: ${officialPriority.id})';
}
