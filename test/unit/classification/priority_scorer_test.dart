import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/features/classification/data/models/prioritization_config.dart';
import 'package:gsuhub/features/classification/domain/priority_scorer.dart';

/// The weighted priority score (manuscript §3.4, Tables 3.2–3.5;
/// Objective 4.B).
void main() {
  final config = PrioritizationConfig.manuscriptDefaults(
    updatedAt: DateTime.utc(2026, 10, 12),
    updatedBy: 'admin-1',
  );
  final scorer = PriorityScorer(config);

  Map<PrioritizationCriterion, int?> rated(
    int severity,
    int safetyRisk,
    int frequency,
    int locationImportance,
  ) => {
    PrioritizationCriterion.severity: severity,
    PrioritizationCriterion.safetyRisk: safetyRisk,
    PrioritizationCriterion.frequency: frequency,
    PrioritizationCriterion.locationImportance: locationImportance,
  };

  test('is the §3.4 formula: Severity weighs most', () {
    // 0.40×4 + 0.30×4 + 0.20×2 + 0.10×3 = 3.50
    expect(scorer.score(rated(4, 4, 2, 3)), 3.50);
    // 0.40×2 + 0.30×2 + 0.20×1 + 0.10×3 = 1.90
    expect(scorer.score(rated(2, 2, 1, 3)), 1.90);
    // Severity moves the score most: one step up adds 0.40.
    expect(scorer.score(rated(3, 2, 1, 3)), 2.30);
  });

  test('every criterion at one rating scores that rating', () {
    for (final rating in [1, 2, 3, 4]) {
      expect(
        scorer.score(rated(rating, rating, rating, rating)),
        rating.toDouble(),
      );
    }
  });

  test('rounds to two decimals, so a score on a band edge stays on it', () {
    // 0.40×3 + 0.30×2 + 0.20×2 + 0.10×3 is 2.5000000000000004 in floating
    // point; by hand, and in Table 3.5, it is 2.50, the start of HIGH.
    expect(scorer.score(rated(3, 2, 2, 3)), 2.50);
    expect(scorer.recommend(rated(3, 2, 2, 3)), PriorityLevel.high);
  });

  test('gives no score until all four criteria are rated', () {
    expect(scorer.score({PrioritizationCriterion.severity: 4}), isNull);
    expect(
      scorer.recommend({
        PrioritizationCriterion.severity: 4,
        PrioritizationCriterion.safetyRisk: 4,
        PrioritizationCriterion.frequency: 4,
        PrioritizationCriterion.locationImportance: null,
      }),
      isNull,
    );
  });

  test('refuses a rating off the 1–4 scale', () {
    expect(() => scorer.score(rated(5, 1, 1, 1)), throwsArgumentError);
    expect(() => scorer.score(rated(1, 1, 0, 1)), throwsArgumentError);
  });

  test("reads Table 3.5's bands", () {
    expect(scorer.levelFor(4.00), PriorityLevel.critical);
    expect(scorer.levelFor(3.50), PriorityLevel.critical);
    expect(scorer.levelFor(3.49), PriorityLevel.high);
    expect(scorer.levelFor(2.50), PriorityLevel.high);
    expect(scorer.levelFor(2.49), PriorityLevel.medium);
    expect(scorer.levelFor(1.50), PriorityLevel.medium);
    expect(scorer.levelFor(1.49), PriorityLevel.low);
    expect(scorer.levelFor(1.00), PriorityLevel.low);
  });

  test("keeps Table 3.2's integer weights on the same 1–4 scale", () {
    final integer = PriorityScorer(
      config.copyWith(activeScheme: PrioritizationScheme.integerWeights),
    );

    // (3×4 + 4×4 + 2×2 + 3×3) ÷ 12 = 3.42: HIGH, where the formula's
    // weights make the same ratings CRITICAL.
    expect(integer.score(rated(4, 4, 2, 3)), 3.42);
    expect(integer.recommend(rated(4, 4, 2, 3)), PriorityLevel.high);
    expect(integer.score(rated(4, 4, 4, 4)), 4.00);
  });

  test('suggests a Frequency rating from the count of similar reports', () {
    // Bands 2, 3, 5: one report (this one) is Low; 2 Moderate; 3–4 High;
    // 5 or more Very High.
    expect(scorer.frequencyRatingFor(0), 1);
    expect(scorer.frequencyRatingFor(1), 1);
    expect(scorer.frequencyRatingFor(2), 2);
    expect(scorer.frequencyRatingFor(3), 3);
    expect(scorer.frequencyRatingFor(4), 3);
    expect(scorer.frequencyRatingFor(5), 4);
    expect(scorer.frequencyRatingFor(40), 4);
  });

  test('names the ratings as Table 3.4 does', () {
    expect([1, 2, 3, 4].map(ratingLabel), [
      'Low',
      'Moderate',
      'High',
      'Very High',
    ]);
  });
}
