import '../../../core/enums/priority_level.dart';
import '../data/models/prioritization_config.dart';

/// Table 3.4's word for a criterion rating: 1 Low, 2 Moderate, 3 High,
/// 4 Very High.
String ratingLabel(int rating) => switch (rating) {
  1 => 'Low',
  2 => 'Moderate',
  3 => 'High',
  4 => 'Very High',
  _ => '$rating',
};

/// The weighted priority score and the level it recommends (manuscript
/// §3.4, Tables 3.2–3.5; Objective 4.B).
///
/// Priority Score = Σ weight × rating ÷ Σ weight, each criterion rated
/// 1–4. With the §3.4 formula's weights (0.40, 0.30, 0.20, 0.10 — Chris's
/// choice) the divisor is 1 and this is the manuscript's formula exactly.
/// Dividing by the weights' sum keeps any other scheme — Table 3.2's
/// integers sum to 12 — on the same 1.00–4.00 scale that Table 3.5's bands
/// assume, so switching schemes never produces a score the bands cannot
/// read.
///
/// The result is decision support only (§1.5): an administrator sets the
/// official priority, and may confirm or change what this recommends.
class PriorityScorer {
  const PriorityScorer(this.config);

  final PrioritizationConfig config;

  /// The score for [ratings], rounded to two decimals as Table 3.5 writes
  /// its bands, or null until every criterion is rated.
  ///
  /// Throws [ArgumentError] for a rating outside the configured scale: that
  /// is a defect in the caller, not a report to score.
  double? score(Map<PrioritizationCriterion, int?> ratings) {
    final weights = config.activeWeights;
    var weighted = 0.0;
    var totalWeight = 0.0;
    for (final criterion in PrioritizationCriterion.values) {
      final rating = ratings[criterion];
      if (rating == null) return null;
      if (rating < config.minRating || rating > config.maxRating) {
        throw ArgumentError.value(
          rating,
          criterion.id,
          'Ratings run from ${config.minRating} to ${config.maxRating}',
        );
      }
      final weight = weights[criterion]!;
      weighted += weight * rating;
      totalWeight += weight;
    }
    // Rounded before it meets the bands, so 3.4999999 from floating-point
    // arithmetic reads as the 3.50 a person computing by hand would get.
    return (weighted / totalWeight * 100).roundToDouble() / 100;
  }

  /// The level whose band [score] falls in (Table 3.5): the highest level
  /// whose lower bound the score reaches.
  PriorityLevel levelFor(double score) {
    final byBound = [...PriorityLevel.values]
      ..sort((a, b) => config.thresholds[b]!.compareTo(config.thresholds[a]!));
    for (final level in byBound) {
      if (score >= config.thresholds[level]!) return level;
    }
    return byBound.last;
  }

  /// [levelFor] the [score] of [ratings], or null until every criterion is
  /// rated.
  PriorityLevel? recommend(Map<PrioritizationCriterion, int?> ratings) {
    final value = score(ratings);
    return value == null ? null : levelFor(value);
  }

  /// The Frequency rating suggested by how many reports of the same damage
  /// at the same facility arrived in [PrioritizationConfig.frequencyWindowDays]
  /// — the report being rated included (Chris's decision, 2026-10-12).
  int frequencyRatingFor(int reportCount) {
    var rating = config.minRating;
    for (final count in config.frequencyBands) {
      if (reportCount >= count) rating++;
    }
    return rating.clamp(config.minRating, config.maxRating);
  }
}
