import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/classification/data/models/classification_rules_config.dart';
import 'package:gsuhub/features/classification/data/models/duplicate_detection_config.dart';
import 'package:gsuhub/features/classification/data/models/prioritization_config.dart';
import 'package:gsuhub/features/classification/data/repositories/config_repository.dart';

import '../../../../core/data/firestore_repository.dart';

/// Firestore-backed [ConfigRepository] for the three fixed-id `config/*`
/// documents.
/// Objective 1 moved this data to Supabase; the app uses [ConfigRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreConfigRepository extends FirestoreRepository
    implements ConfigRepository {
  const FirestoreConfigRepository({required super.db, required super.guard});

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
