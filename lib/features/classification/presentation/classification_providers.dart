import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/damage_categories.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../reporting/presentation/report_providers.dart';
import '../data/models/classification_rules_config.dart';
import '../data/models/duplicate_detection_config.dart';
import '../data/models/prioritization_config.dart';
import '../domain/duplicate_detector.dart';
import '../domain/keyword_classifier.dart';

/// The `updatedBy` of a config the app made up from the manuscript because
/// the project has none saved — a live project before an administrator
/// saves one. The Settings page uses it to say the list is not saved yet.
const String manuscriptDefaultsAuthor = 'manuscript';

final DateTime _defaultsDate = DateTime.utc(2026);

/// [result], or [fallback] when the document does not exist. Any other
/// failure stays a failure: a network or permission problem is not a
/// missing document, and the screens must say so rather than quietly
/// apply defaults.
Result<T> _orDefault<T>(Result<T> result, T Function() fallback) =>
    switch (result) {
      Error(failure: NotFoundFailure()) => Result.success(fallback()),
      _ => result,
    };

ClassificationRulesConfig _defaultKeywords() =>
    ClassificationRulesConfig.seededFromManuscript(
      updatedAt: _defaultsDate,
      updatedBy: manuscriptDefaultsAuthor,
    );

/// The live keyword dictionary (Objective 4.A), or Table 3.3's keywords
/// when the project has none saved.
final keywordRulesProvider =
    StreamProvider.autoDispose<Result<ClassificationRulesConfig>>(
      (ref) => ref
          .watch(configRepositoryProvider)
          .watchClassificationRules()
          .map((result) => _orDefault(result, _defaultKeywords)),
    );

/// The live weights and bands (Objective 4.B), or the manuscript's — the
/// §3.4 formula's weights, Chris's choice — when none are saved.
final prioritizationConfigProvider =
    StreamProvider.autoDispose<Result<PrioritizationConfig>>(
      (ref) => ref
          .watch(configRepositoryProvider)
          .watchPrioritization()
          .map(
            (result) => _orDefault(
              result,
              () => PrioritizationConfig.manuscriptDefaults(
                updatedAt: _defaultsDate,
                updatedBy: manuscriptDefaultsAuthor,
              ),
            ),
          ),
    );

/// The live duplicate-detection settings (Objective 4.C), or the defaults
/// when none are saved.
final duplicateDetectionConfigProvider =
    StreamProvider.autoDispose<Result<DuplicateDetectionConfig>>(
      (ref) => ref
          .watch(configRepositoryProvider)
          .watchDuplicateDetection()
          .map(
            (result) => _orDefault(
              result,
              () => DuplicateDetectionConfig.defaults(
                updatedAt: _defaultsDate,
                updatedBy: manuscriptDefaultsAuthor,
              ),
            ),
          ),
    );

/// Classifies a report as it is filed (Objective 4.A), on the phone: there
/// is no server on the Spark plan to do it later.
class ReportClassifier {
  const ReportClassifier(this._ref);

  final Ref _ref;

  /// The damage type the keyword dictionary finds in [title] and
  /// [description], or null when none matched, two tied, or the dictionary
  /// could not be read. The report is filed either way: unclassified, it
  /// goes to an administrator, as §3.4 provides for any unmatched report.
  Future<DamageCategory?> classify({
    required String title,
    required String description,
  }) async {
    final read = await _ref
        .read(configRepositoryProvider)
        .getClassificationRules();
    final rules = switch (_orDefault(read, _defaultKeywords)) {
      Success(:final value) => value,
      Error() => null,
    };
    if (rules == null) return null;
    return KeywordClassifier(rules)
        .classify(
          KeywordClassifier.textOf(title: title, description: description),
        )
        .category;
  }
}

final reportClassifierProvider = Provider<ReportClassifier>(
  ReportClassifier.new,
);

/// The Frequency hint's question (Objective 4.B): reports of [category] at
/// [facilityId] in the last [windowDays].
typedef SimilarReportsQuery = ({
  String facilityId,
  DamageCategory category,
  int windowDays,
});

/// How many reports answer a [SimilarReportsQuery], the report being rated
/// included. Read once per question: the hint is a starting point for the
/// administrator, not a live figure.
final similarReportCountProvider = FutureProvider.autoDispose
    .family<Result<int>, SimilarReportsQuery>(
      (ref, query) => ref
          .watch(damageReportRepositoryProvider)
          .countSimilarReports(
            facilityId: query.facilityId,
            category: query.category,
            since: DateTime.now().toUtc().subtract(
              Duration(days: query.windowDays),
            ),
          ),
    );

/// Possible duplicates of every report that has any, among the reports the
/// console has loaded (Objective 4.C). Computed in memory: the console
/// already holds every report that is not a merged duplicate, and the
/// detector compares them without another read.
final duplicateFlagsProvider =
    Provider.autoDispose<
      AsyncValue<Result<Map<String, List<DuplicateCandidate>>>>
    >((ref) {
      final reports = ref.watch(reportsStreamProvider);
      final config = ref.watch(duplicateDetectionConfigProvider);
      return switch ((reports, config)) {
        (AsyncData(value: final loaded), AsyncData(value: final settings)) =>
          AsyncData(switch ((loaded, settings)) {
            (Success(value: final list), Success(value: final rules)) =>
              Result.success(DuplicateDetector(rules).flagsFor(list)),
            (Error(:final failure), _) ||
            (_, Error(:final failure)) => Result.failure(failure),
          }),
        (AsyncError(:final error, :final stackTrace), _) ||
        (
          _,
          AsyncError(:final error, :final stackTrace),
        ) => AsyncError(error, stackTrace),
        _ => const AsyncLoading(),
      };
    });

/// The possible duplicates of one report (Objective 4.C), most alike first.
final duplicateCandidatesProvider = Provider.autoDispose
    .family<AsyncValue<Result<List<DuplicateCandidate>>>, String>(
      (ref, reportId) => ref
          .watch(duplicateFlagsProvider)
          .whenData(
            (result) => result.map(
              (flags) => flags[reportId] ?? const <DuplicateCandidate>[],
            ),
          ),
    );
