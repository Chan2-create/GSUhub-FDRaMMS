import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/utils/result.dart';
import '../models/classification_rules_config.dart';
import '../models/duplicate_detection_config.dart';
import '../models/prioritization_config.dart';
import 'config_repository.dart';

/// Firestore-backed [ConfigRepository] for the three fixed-id `config/*`
/// documents.
class ConfigRepositoryImpl extends FirestoreRepository
    implements ConfigRepository {
  const ConfigRepositoryImpl({required super.db, required super.guard});

  static const String _path = FirestorePaths.config;

  /// Fixed document ids. These are addressed by name rather than queried,
  /// so they are constants rather than data.
  static const String classificationRulesId = 'classification_rules';
  static const String prioritizationId = 'prioritization';
  static const String duplicateDetectionId = 'duplicate_detection';

  @override
  Future<Result<ClassificationRulesConfig>> getClassificationRules() => getOne(
    path: _path,
    id: classificationRulesId,
    convert: ClassificationRulesConfig.fromFirestore,
  );

  @override
  Stream<Result<ClassificationRulesConfig>> watchClassificationRules() =>
      watchOne(
        path: _path,
        id: classificationRulesId,
        convert: ClassificationRulesConfig.fromFirestore,
      );

  @override
  Future<Result<void>> updateClassificationRules(
    ClassificationRulesConfig config,
  ) => setDoc(
    path: _path,
    id: classificationRulesId,
    data: config.toFirestore(),
  );

  @override
  Future<Result<PrioritizationConfig>> getPrioritization() => getOne(
    path: _path,
    id: prioritizationId,
    convert: PrioritizationConfig.fromFirestore,
  );

  @override
  Stream<Result<PrioritizationConfig>> watchPrioritization() => watchOne(
    path: _path,
    id: prioritizationId,
    convert: PrioritizationConfig.fromFirestore,
  );

  @override
  Future<Result<void>> updatePrioritization(PrioritizationConfig config) =>
      setDoc(path: _path, id: prioritizationId, data: config.toFirestore());

  @override
  Future<Result<DuplicateDetectionConfig>> getDuplicateDetection() => getOne(
    path: _path,
    id: duplicateDetectionId,
    convert: DuplicateDetectionConfig.fromFirestore,
  );

  @override
  Stream<Result<DuplicateDetectionConfig>> watchDuplicateDetection() =>
      watchOne(
        path: _path,
        id: duplicateDetectionId,
        convert: DuplicateDetectionConfig.fromFirestore,
      );

  @override
  Future<Result<void>> updateDuplicateDetection(
    DuplicateDetectionConfig config,
  ) =>
      setDoc(path: _path, id: duplicateDetectionId, data: config.toFirestore());
}
