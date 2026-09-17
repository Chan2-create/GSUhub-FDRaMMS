import '../../../../core/utils/result.dart';
import '../models/classification_rules_config.dart';
import '../models/duplicate_detection_config.dart';
import '../models/prioritization_config.dart';

/// Abstract contract for the three `config/*` documents that parameterize
/// the rule-based engine: classification keywords, prioritization weights,
/// and duplicate-detection thresholds.
///
/// These are data rather than constants because §1.5 constrains the
/// mechanism to "predefined keywords, categories, criteria, ratings, and
/// assigned weights" with no machine learning — a rule engine GSU staff
/// cannot retune without a rebuild would not survive contact with a real
/// maintenance office.
///
/// Each getter is also exposed as a stream: a keyword or weight edited in
/// the Admin console should take effect without restarting the apps.
///
/// **Interface only** — implementation is 1.C.
abstract interface class ConfigRepository {
  Future<Result<ClassificationRulesConfig>> getClassificationRules();

  Stream<Result<ClassificationRulesConfig>> watchClassificationRules();

  Future<Result<void>> updateClassificationRules(
    ClassificationRulesConfig config,
  );

  Future<Result<PrioritizationConfig>> getPrioritization();

  Stream<Result<PrioritizationConfig>> watchPrioritization();

  /// Updates the weighting configuration.
  ///
  /// Note that changing `activeScheme` retroactively changes what a
  /// recomputed score means — it does **not** rewrite scores already
  /// stored on existing reports. Whether historical reports should be
  /// rescored after a scheme change is a policy question for the GSU,
  /// bundled with the unresolved weight conflict (see
  /// [PrioritizationConfig] and docs/data_dictionary.md).
  Future<Result<void>> updatePrioritization(PrioritizationConfig config);

  Future<Result<DuplicateDetectionConfig>> getDuplicateDetection();

  Stream<Result<DuplicateDetectionConfig>> watchDuplicateDetection();

  Future<Result<void>> updateDuplicateDetection(
    DuplicateDetectionConfig config,
  );
}
