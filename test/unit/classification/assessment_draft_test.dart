import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/features/classification/data/models/prioritization_config.dart';
import 'package:gsuhub/features/classification/domain/priority_scorer.dart';
import 'package:gsuhub/features/classification/presentation/assessment_draft.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';

/// The review panel's working state (Objectives 4.A–4.C).
void main() {
  final now = DateTime.utc(2026, 10, 12, 9);
  final scorer = PriorityScorer(
    PrioritizationConfig.manuscriptDefaults(
      updatedAt: now,
      updatedBy: 'admin-1',
    ),
  );

  DamageReport report({
    DamageCategory? category = DamageCategory.plumbing,
    bool classifiedAutomatically = true,
    int? severity,
    int? safetyRisk,
    int? frequency,
    int? locationImportance,
    PriorityLevel? officialPriority,
  }) => DamageReport(
    id: 'rep-1',
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: 'Leaking pipe',
    description: 'Under the sink.',
    category: category,
    classifiedAutomatically: classifiedAutomatically,
    requestorPriority: PriorityLevel.medium,
    severityRating: severity,
    safetyRiskRating: safetyRisk,
    frequencyRating: frequency,
    locationImportanceRating: locationImportance,
    officialPriority: officialPriority,
    status: ReportStatus.underReview,
    submittedAt: now,
    updatedAt: now,
  );

  AssessmentDraft rateAll(AssessmentDraft draft, int s, int r, int f, int l) =>
      draft
          .withRating(PrioritizationCriterion.severity, s)
          .withRating(PrioritizationCriterion.safetyRisk, r)
          .withRating(PrioritizationCriterion.frequency, f)
          .withRating(PrioritizationCriterion.locationImportance, l);

  group('starts from', () {
    test("the classifier's damage type on a report not yet reviewed", () {
      final draft = AssessmentDraft.of(report());

      expect(draft.category, DamageCategory.plumbing);
      expect(draft.ratings, isEmpty);
      expect(draft.officialChosen, isFalse);
    });

    test("today's keyword match when the report has no type", () {
      final draft = AssessmentDraft.of(
        report(category: null, classifiedAutomatically: false),
        suggestion: DamageCategory.electrical,
      );

      expect(draft.category, DamageCategory.electrical);
    });

    test('a saved assessment, with its official level fixed', () {
      final draft = AssessmentDraft.of(
        report(
          severity: 3,
          safetyRisk: 2,
          frequency: 1,
          locationImportance: 4,
          officialPriority: PriorityLevel.critical,
        ),
      );

      expect(draft.ratings, {
        PrioritizationCriterion.severity: 3,
        PrioritizationCriterion.safetyRisk: 2,
        PrioritizationCriterion.frequency: 1,
        PrioritizationCriterion.locationImportance: 4,
      });
      expect(draft.officialChosen, isTrue);
      // A saved decision does not follow the recommendation.
      expect(draft.officialFor(PriorityLevel.low), PriorityLevel.critical);
    });
  });

  test('the Frequency hint stands in until a Frequency is picked', () {
    final draft = AssessmentDraft.of(report());

    expect(draft.ratingsWith(3)[PrioritizationCriterion.frequency], 3);
    expect(draft.ratingsWith(null), isEmpty);

    final picked = draft.withRating(PrioritizationCriterion.frequency, 1);
    expect(picked.ratingsWith(3)[PrioritizationCriterion.frequency], 1);
  });

  test('the official level follows the recommendation until one is picked', () {
    final draft = AssessmentDraft.of(report());

    expect(draft.officialFor(PriorityLevel.high), PriorityLevel.high);
    expect(
      draft
          .withOfficial(PriorityLevel.critical)
          .officialFor(PriorityLevel.high),
      PriorityLevel.critical,
    );
  });

  group('toAssessment', () {
    test('is null while the type or any rating is missing', () {
      final stored = report(category: null, classifiedAutomatically: false);
      final draft = AssessmentDraft.of(stored);

      expect(
        rateAll(
          draft,
          4,
          4,
          2,
          3,
        ).toAssessment(report: stored, scorer: scorer, suggestion: null),
        isNull,
        reason: 'no damage type',
      );
      expect(
        draft
            .withCategory(DamageCategory.plumbing)
            .withRating(PrioritizationCriterion.severity, 4)
            .toAssessment(report: stored, scorer: scorer, suggestion: null),
        isNull,
        reason: 'three criteria unrated',
      );
    });

    test('scores, recommends, and confirms the recommendation', () {
      final stored = report();
      final assessment = rateAll(AssessmentDraft.of(stored), 4, 4, 2, 3)
          .toAssessment(
            report: stored,
            scorer: scorer,
            suggestion: DamageCategory.plumbing,
          )!;

      expect(assessment.priorityScore, 3.50);
      expect(assessment.recommendedPriority, PriorityLevel.critical);
      expect(assessment.officialPriority, PriorityLevel.critical);
      expect(assessment.modifiesRecommendation, isFalse);
      // The classifier's type, confirmed, stays marked automatic.
      expect(assessment.classifiedAutomatically, isTrue);
    });

    test('takes the Frequency hint when no Frequency was picked', () {
      final stored = report();
      final draft = AssessmentDraft.of(stored)
          .withRating(PrioritizationCriterion.severity, 2)
          .withRating(PrioritizationCriterion.safetyRisk, 2)
          .withRating(PrioritizationCriterion.locationImportance, 3);

      final assessment = draft.toAssessment(
        report: stored,
        scorer: scorer,
        suggestion: DamageCategory.plumbing,
        frequencyHint: 1,
      )!;

      expect(assessment.frequencyRating, 1);
      expect(assessment.priorityScore, 1.90);
      expect(assessment.recommendedPriority, PriorityLevel.medium);
    });

    test('records a changed level as a change', () {
      final stored = report();
      final assessment = rateAll(AssessmentDraft.of(stored), 2, 2, 1, 3)
          .withOfficial(PriorityLevel.high)
          .toAssessment(
            report: stored,
            scorer: scorer,
            suggestion: DamageCategory.plumbing,
          )!;

      expect(assessment.recommendedPriority, PriorityLevel.medium);
      expect(assessment.officialPriority, PriorityLevel.high);
      expect(assessment.modifiesRecommendation, isTrue);
    });

    test("a type other than the classifier's becomes the administrator's", () {
      final stored = report();
      final assessment = rateAll(AssessmentDraft.of(stored), 2, 2, 1, 3)
          .withCategory(DamageCategory.structural)
          .toAssessment(
            report: stored,
            scorer: scorer,
            suggestion: DamageCategory.plumbing,
          )!;

      expect(assessment.category, DamageCategory.structural);
      expect(assessment.classifiedAutomatically, isFalse);
    });
  });
}
