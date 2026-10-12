import 'dart:async';

import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/classification/data/models/classification_rules_config.dart';
import 'package:gsuhub/features/classification/data/models/duplicate_detection_config.dart';
import 'package:gsuhub/features/classification/data/models/prioritization_config.dart';
import 'package:gsuhub/features/classification/data/repositories/config_repository.dart';

/// The three `config/*` documents, held in memory (Objectives 4.A–4.C).
///
/// By default holds the manuscript's keywords, weights and bands, and the
/// duplicate defaults, as the seeded emulator does. Pass null for one to
/// describe a project that has none saved — the app then falls back to
/// the same defaults — or a [Result.failure] to describe a broken read.
class FakeConfigRepository implements ConfigRepository {
  FakeConfigRepository({
    Result<ClassificationRulesConfig>? keywords,
    Result<PrioritizationConfig>? prioritization,
    Result<DuplicateDetectionConfig>? duplicates,
    bool savedKeywords = true,
    this.saveFailure,
  }) : _keywords =
           keywords ??
           (savedKeywords
               ? Result.success(
                   ClassificationRulesConfig.seededFromManuscript(
                     updatedAt: savedAt,
                     updatedBy: 'admin-1',
                   ),
                 )
               : _missing<ClassificationRulesConfig>()),
       _prioritization =
           prioritization ??
           Result.success(
             PrioritizationConfig.manuscriptDefaults(
               updatedAt: savedAt,
               updatedBy: 'admin-1',
             ),
           ),
       _duplicates =
           duplicates ??
           Result.success(
             DuplicateDetectionConfig.defaults(
               updatedAt: savedAt,
               updatedBy: 'admin-1',
             ),
           );

  /// When the stand-in documents were saved.
  static final DateTime savedAt = DateTime.utc(2026, 10, 1, 8);

  static Result<T> _missing<T>() => const Result.failure(
    NotFoundFailure('The requested record no longer exists.'),
  );

  Result<ClassificationRulesConfig> _keywords;
  final Result<PrioritizationConfig> _prioritization;
  final Result<DuplicateDetectionConfig> _duplicates;

  /// Returned by every save instead of saving, when set.
  final Failure? saveFailure;

  /// Replaces the keyword dictionary, as an outside change would.
  set keywords(Result<ClassificationRulesConfig> result) {
    _keywords = result;
    _keywordChanges.add(result);
  }

  /// Every keyword dictionary saved, in order.
  final savedKeywordLists = <ClassificationRulesConfig>[];

  final _keywordChanges =
      StreamController<Result<ClassificationRulesConfig>>.broadcast();

  @override
  Future<Result<ClassificationRulesConfig>> getClassificationRules() async =>
      _keywords;

  @override
  Stream<Result<ClassificationRulesConfig>> watchClassificationRules() async* {
    yield _keywords;
    yield* _keywordChanges.stream;
  }

  @override
  Future<Result<void>> updateClassificationRules(
    ClassificationRulesConfig config,
  ) async {
    if (saveFailure case final failure?) return Result.failure(failure);
    savedKeywordLists.add(config);
    _keywords = Result.success(config);
    _keywordChanges.add(_keywords);
    return const Result.success(null);
  }

  @override
  Future<Result<PrioritizationConfig>> getPrioritization() async =>
      _prioritization;

  @override
  Stream<Result<PrioritizationConfig>> watchPrioritization() =>
      Stream.value(_prioritization);

  @override
  Future<Result<void>> updatePrioritization(PrioritizationConfig config) =>
      throw UnimplementedError('No screen saves the weights.');

  @override
  Future<Result<DuplicateDetectionConfig>> getDuplicateDetection() async =>
      _duplicates;

  @override
  Stream<Result<DuplicateDetectionConfig>> watchDuplicateDetection() =>
      Stream.value(_duplicates);

  @override
  Future<Result<void>> updateDuplicateDetection(
    DuplicateDetectionConfig config,
  ) => throw UnimplementedError('No screen saves the duplicate settings.');
}
