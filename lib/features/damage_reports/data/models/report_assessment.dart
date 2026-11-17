import 'package:flutter/foundation.dart';

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/utils/record_converters.dart';

/// An administrator's review of one report's classification and priority
/// (Objectives 4.A–4.C): the damage type they confirm or choose, the four
/// criterion ratings, the score and recommended level the weighted formula
/// gives, and the official priority they set.
///
/// Saved in one write, so a report never carries an official priority
/// without the ratings behind it, or ratings without the score they give.
///
/// What the requestor chose when filing is no part of it: a review is
/// recorded beside the requestor's damage type and urgency, never over
/// them (2026-11-16).
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
    String? reason,
  }) : reason = _cleaned(reason) {
    for (final (field, rating) in [
      ('severityRating', severityRating),
      ('safetyRiskRating', safetyRiskRating),
      ('frequencyRating', frequencyRating),
      ('locationImportanceRating', locationImportanceRating),
    ]) {
      RecordConverters.validateRange(rating, 1, 4, field);
    }
    RecordConverters.validateRange(priorityScore, 1.0, 4.0, 'priorityScore');
    RecordConverters.validateRange(
      this.reason?.length ?? 0,
      0,
      reasonLimit,
      'reason',
    );
  }

  /// The longest reason accepted, as the database holds it to.
  static const int reasonLimit = 500;

  static String? _cleaned(String? reason) {
    final trimmed = reason?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
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

  /// Why the administrator decided as they did, when they said: kept with
  /// the decision in the report's audit trail. Null when not given.
  final String? reason;

  /// This review, for [reason].
  ReportAssessment withReason(String? reason) => ReportAssessment(
    category: category,
    classifiedAutomatically: classifiedAutomatically,
    severityRating: severityRating,
    safetyRiskRating: safetyRiskRating,
    frequencyRating: frequencyRating,
    locationImportanceRating: locationImportanceRating,
    priorityScore: priorityScore,
    recommendedPriority: recommendedPriority,
    officialPriority: officialPriority,
    reason: reason,
  );

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
      other.officialPriority == officialPriority &&
      other.reason == reason;

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
    reason,
  );

  @override
  String toString() =>
      'ReportAssessment(${category.id}, score: $priorityScore, '
      'recommended: ${recommendedPriority.id}, '
      'official: ${officialPriority.id})';
}
