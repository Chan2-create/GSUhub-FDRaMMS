import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/damage_categories.dart';
import '../../../core/enums/priority_level.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../../core/widgets/section_card.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../reporting/data/models/report_assessment.dart';
import '../../reporting/presentation/report_review_controller.dart';
import '../data/models/classification_rules_config.dart';
import '../data/models/prioritization_config.dart';
import '../domain/keyword_classifier.dart';
import '../domain/priority_scorer.dart';
import 'assessment_draft.dart';
import 'classification_providers.dart';

/// Where an administrator confirms a report's damage type, rates the four
/// priority criteria, and sets the official priority (Objectives 4.A–4.C).
///
/// No Figma frame exists for it; it is built from the console's own
/// components, like the rest of the report page. Shown only while the
/// report can still be assessed ([DamageReport.canBeAssessed]).
class ReportAssessmentPanel extends ConsumerWidget {
  const ReportAssessmentPanel({required this.report, super.key});

  final DamageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
    title: 'Classification and priority',
    subtitle:
        'Confirm the damage type and set the official priority before the '
        'work is assigned.',
    child: AsyncValueView<ClassificationRulesConfig>(
      value: ref.watch(keywordRulesProvider),
      onRetry: () => ref.invalidate(keywordRulesProvider),
      data: (rules) => AsyncValueView<PrioritizationConfig>(
        value: ref.watch(prioritizationConfigProvider),
        onRetry: () => ref.invalidate(prioritizationConfigProvider),
        data: (config) => _AssessmentForm(
          // A fresh form whenever the saved assessment changes — after this
          // administrator saves, or another one does — but not when only
          // the status moves, which would throw away unsaved ratings.
          key: ValueKey(_savedAssessmentOf(report)),
          report: report,
          rules: rules,
          config: config,
        ),
      ),
    ),
  );

  static String _savedAssessmentOf(DamageReport report) => [
    report.id,
    report.category?.id,
    report.classifiedAutomatically,
    report.severityRating,
    report.safetyRiskRating,
    report.frequencyRating,
    report.locationImportanceRating,
    report.officialPriority?.id,
  ].join('|');
}

class _AssessmentForm extends ConsumerStatefulWidget {
  const _AssessmentForm({
    required this.report,
    required this.rules,
    required this.config,
    super.key,
  });

  final DamageReport report;
  final ClassificationRulesConfig rules;
  final PrioritizationConfig config;

  @override
  ConsumerState<_AssessmentForm> createState() => _AssessmentFormState();
}

class _AssessmentFormState extends ConsumerState<_AssessmentForm> {
  late ClassificationResult _keywords = _classify();
  late AssessmentDraft _draft = AssessmentDraft.of(
    widget.report,
    suggestion: _keywords.category,
  );
  bool _saving = false;

  ClassificationResult _classify() => KeywordClassifier(widget.rules).classify(
    KeywordClassifier.textOf(
      title: widget.report.title,
      description: widget.report.description,
    ),
  );

  @override
  void didUpdateWidget(covariant _AssessmentForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keywords saved on the Settings page meanwhile: the evidence shown
    // follows them. What the administrator has picked stays as picked.
    if (widget.rules != oldWidget.rules) _keywords = _classify();
  }

  PriorityScorer get _scorer => PriorityScorer(widget.config);

  /// The Frequency rating the count of similar reports suggests, once it
  /// is known.
  int? _frequencyHint(AsyncValue<Result<int>>? count) => switch (count) {
    AsyncData(value: Success(value: final reports)) =>
      _scorer.frequencyRatingFor(reports),
    _ => null,
  };

  Future<void> _save(ReportAssessment assessment) async {
    setState(() => _saving = true);
    final result = await ref
        .read(reportReviewControllerProvider)
        .recordAssessment(widget.report.id, assessment);
    if (!mounted) return;
    setState(() => _saving = false);

    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (_) => messenger.showSnackBar(
        const SnackBar(content: Text('Classification and priority saved.')),
      ),
      (failure) => messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final category = _draft.category;
    final facilityId = report.facilityId;

    final countQuery = category == null || facilityId == null
        ? null
        : (
            facilityId: facilityId,
            category: category,
            windowDays: widget.config.frequencyWindowDays,
          );
    final count = countQuery == null
        ? null
        : ref.watch(similarReportCountProvider(countQuery));
    final hint = _frequencyHint(count);

    final ratings = _draft.ratingsWith(hint);
    final score = _scorer.score(ratings);
    final recommended = score == null ? null : _scorer.levelFor(score);
    final official = _draft.officialFor(recommended);
    final assessment = _draft.toAssessment(
      report: report,
      scorer: _scorer,
      suggestion: _keywords.category,
      frequencyHint: hint,
    );
    final saved =
        assessment != null &&
        report.officialPriority == assessment.officialPriority &&
        report.category == assessment.category &&
        report.severityRating == assessment.severityRating &&
        report.safetyRiskRating == assessment.safetyRiskRating &&
        report.frequencyRating == assessment.frequencyRating &&
        report.locationImportanceRating == assessment.locationImportanceRating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Damage type'),
        const SizedBox(height: 8),
        SizedBox(
          width: 320,
          child: DropdownButtonFormField<DamageCategory>(
            initialValue: category,
            isExpanded: true,
            hint: const Text('Choose the damage type'),
            items: [
              for (final option in DamageCategory.values)
                DropdownMenuItem(value: option, child: Text(option.label)),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _draft = _draft.withCategory(value));
                    }
                  },
          ),
        ),
        const SizedBox(height: 8),
        _KeywordEvidence(result: _keywords),
        if (report.requestorCategory case final suggested?) ...[
          const SizedBox(height: 4),
          Text(
            'The requestor suggested ${suggested.label}.',
            style: AppTextStyles.bodySmall,
          ),
        ],
        const _Divider(),
        const _Heading('Priority criteria'),
        const SizedBox(height: 4),
        Text(
          'Rate each from ${widget.config.minRating} (Low) to '
          '${widget.config.maxRating} (Very High), as in Table 3.4.',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final criterion in PrioritizationCriterion.values)
          _CriterionRow(
            criterion: criterion,
            weight: widget.config.activeWeights[criterion]!,
            minRating: widget.config.minRating,
            maxRating: widget.config.maxRating,
            value: ratings[criterion],
            enabled: !_saving,
            onChanged: (rating) =>
                setState(() => _draft = _draft.withRating(criterion, rating)),
            footnote: criterion == PrioritizationCriterion.frequency
                ? _FrequencyNote(
                    category: category,
                    hasFacility: facilityId != null,
                    count: count,
                    hint: hint,
                    usingHint:
                        hint != null &&
                        !_draft.ratings.containsKey(
                          PrioritizationCriterion.frequency,
                        ),
                    windowDays: widget.config.frequencyWindowDays,
                  )
                : null,
          ),
        const _Divider(),
        _ScoreLine(
          score: score,
          recommended: recommended,
          config: widget.config,
        ),
        const _Divider(),
        const _Heading('Official priority'),
        const SizedBox(height: 8),
        SegmentedButton<PriorityLevel>(
          key: const ValueKey('official-priority'),
          segments: [
            for (final level in PriorityLevel.values)
              ButtonSegment(value: level, label: Text(level.title)),
          ],
          selected: {?official},
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          onSelectionChanged: _saving
              ? null
              : (selection) {
                  if (selection.isNotEmpty) {
                    setState(
                      () => _draft = _draft.withOfficial(selection.single),
                    );
                  }
                },
        ),
        const SizedBox(height: 8),
        Text(
          "The requestor's own urgency: ${report.requestorPriority.title}. "
          'It is supplementary and does not set the official level (§1.2).',
          style: AppTextStyles.bodySmall,
        ),
        if (official != null && recommended != null && official != recommended)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Differs from the recommended ${recommended.title}: saving '
              'records it as your change.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            FilledButton(
              onPressed: assessment == null || saved || _saving
                  ? null
                  : () => _save(assessment),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textOnDark,
                      ),
                    )
                  : Text(
                      report.isPriorityConfirmed
                          ? 'Save changes'
                          : 'Confirm classification and priority',
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(switch ((assessment, saved)) {
                (null, _) when category == null => 'Choose the damage type.',
                (null, _) => 'Rate all four criteria.',
                (_, true) => 'Saved.',
                _ => '',
              }, style: AppTextStyles.bodySmall),
            ),
          ],
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: AppTextStyles.fieldLabel);
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Divider(height: 1, color: AppColors.border),
  );
}

/// Why the panel suggests the type it does: which keywords were found.
class _KeywordEvidence extends StatelessWidget {
  const _KeywordEvidence({required this.result});

  final ClassificationResult result;

  @override
  Widget build(BuildContext context) {
    String quoted(Iterable<String> keywords) =>
        keywords.map((keyword) => '“$keyword”').join(', ');

    final text = switch (result) {
      ClassificationResult(category: final category?) =>
        'Keywords found: ${quoted(result.keywordsFor(category))} → '
            '${category.label}.',
      ClassificationResult(isTie: true) =>
        'Keywords for more than one type: '
            '${[for (final match in result.matches) '“${match.keyword}” (${match.category.label})'].join(', ')}. '
            'Choose the type.',
      _ =>
        'No keyword in the title or description matched, so the type is '
            'yours to choose.',
    };
    return Text(text, style: AppTextStyles.bodySmall);
  }
}

/// One criterion: its name, weight and meaning, and four buttons for its
/// 1–4 rating.
class _CriterionRow extends StatelessWidget {
  const _CriterionRow({
    required this.criterion,
    required this.weight,
    required this.minRating,
    required this.maxRating,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.footnote,
  });

  final PrioritizationCriterion criterion;
  final double weight;
  final int minRating;
  final int maxRating;
  final int? value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final Widget? footnote;

  /// The criterion's name, and what it measures — manuscript §3.4's own
  /// definitions.
  static (String, String) describe(PrioritizationCriterion criterion) =>
      switch (criterion) {
        PrioritizationCriterion.severity => (
          'Severity',
          'The extent of the facility damage.',
        ),
        PrioritizationCriterion.safetyRisk => (
          'Safety risk',
          'The potential danger posed to users.',
        ),
        PrioritizationCriterion.frequency => (
          'Frequency',
          'How often the same issue is reported.',
        ),
        PrioritizationCriterion.locationImportance => (
          'Location importance',
          'The operational importance of the affected facility or area.',
        ),
      };

  @override
  Widget build(BuildContext context) {
    final (name, meaning) = describe(criterion);
    final rating = value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: name, style: AppTextStyles.fieldValue),
                      TextSpan(
                        text: '  × ${weight.toStringAsFixed(2)}',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(meaning, style: AppTextStyles.bodySmall),
                ?footnote,
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Semantics(
                label: '$name rating',
                child: SegmentedButton<int>(
                  key: ValueKey('rating-${criterion.id}'),
                  segments: [
                    for (var r = minRating; r <= maxRating; r++)
                      ButtonSegment(
                        value: r,
                        label: Text('$r'),
                        tooltip: ratingLabel(r),
                      ),
                  ],
                  selected: {?rating},
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  onSelectionChanged: enabled
                      ? (selection) {
                          if (selection.isNotEmpty) onChanged(selection.single);
                        }
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                rating == null ? 'Not rated' : ratingLabel(rating),
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Under Frequency: how many similar reports there are, and the rating
/// that suggests.
class _FrequencyNote extends StatelessWidget {
  const _FrequencyNote({
    required this.category,
    required this.hasFacility,
    required this.count,
    required this.hint,
    required this.usingHint,
    required this.windowDays,
  });

  final DamageCategory? category;
  final bool hasFacility;
  final AsyncValue<Result<int>>? count;
  final int? hint;
  final bool usingHint;
  final int windowDays;

  @override
  Widget build(BuildContext context) {
    final type = category;
    final text = switch (count) {
      _ when !hasFacility =>
        'This report names no facility, so similar reports cannot be counted.',
      _ when type == null => 'Choose the damage type to count similar reports.',
      AsyncData(value: Success(value: final reports)) =>
        '$reports ${reports == 1 ? 'report' : 'reports'} of '
            '${type.label} at this facility in the last $windowDays days '
            '(this one included) — suggests $hint, ${ratingLabel(hint!)}'
            '${usingHint ? ', filled in for you' : ''}.',
      AsyncData(value: Error(:final failure)) =>
        'Similar reports could not be counted: ${failure.message}',
      AsyncError() => 'Similar reports could not be counted.',
      _ => 'Counting similar reports…',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
      ),
    );
  }
}

/// The weighted score and the level it recommends, with the formula that
/// gave it — so an administrator, or a panel, can check the arithmetic.
class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    required this.score,
    required this.recommended,
    required this.config,
  });

  final double? score;
  final PriorityLevel? recommended;
  final PrioritizationConfig config;

  @override
  Widget build(BuildContext context) {
    final weights = config.activeWeights;
    final formula = [
      for (final criterion in PrioritizationCriterion.values)
        '${weights[criterion]!.toStringAsFixed(2)} × '
            '${_CriterionRow.describe(criterion).$1}',
    ].join(' + ');
    final bands = [
      for (final level in PriorityLevel.values.reversed)
        '${level.title} from ${config.thresholds[level]!.toStringAsFixed(2)}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Priority score'),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              score?.toStringAsFixed(2) ?? '—',
              style: AppTextStyles.statValue,
            ),
            const SizedBox(width: 16),
            if (recommended case final level?) ...[
              const Text('Recommended', style: AppTextStyles.bodySmall),
              const SizedBox(width: 8),
              PriorityChip(level: level),
            ] else
              const Text(
                'Rate all four criteria to compute the score.',
                style: AppTextStyles.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Score = $formula'
          '${config.activeWeightsAreNormalized ? '' : ', divided by the sum of the weights'}'
          ' (manuscript §3.4). Bands: $bands (Table 3.5). The score is a '
          'recommendation; the official priority is yours to set.',
          style: AppTextStyles.bodySmall,
        ),
      ],
    );
  }
}
