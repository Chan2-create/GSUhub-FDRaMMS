import '../../../../core/data/row_snapshot.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import '../models/classification_rules_config.dart';
import '../models/duplicate_detection_config.dart';
import '../models/prioritization_config.dart';
import 'config_repository.dart';

/// Supabase-backed [ConfigRepository] for the three settings documents
/// (Objective 1). Each is one `app_config` row whose `data` is the
/// document; saving goes through `update_config`, which stamps who saved
/// it and when.
class ConfigRepositoryImpl extends SupabaseRepository
    implements ConfigRepository {
  const ConfigRepositoryImpl({required super.client, required super.guard});

  static const String _table = 'app_config';

  static const String classificationRulesId = 'classification_rules';
  static const String prioritizationId = 'prioritization';
  static const String duplicateDetectionId = 'duplicate_detection';

  @override
  Future<Result<ClassificationRulesConfig>> getClassificationRules() =>
      _get(classificationRulesId, ClassificationRulesConfig.fromFirestore);

  @override
  Stream<Result<ClassificationRulesConfig>> watchClassificationRules() =>
      _watch(classificationRulesId, ClassificationRulesConfig.fromFirestore);

  @override
  Future<Result<void>> updateClassificationRules(
    ClassificationRulesConfig config,
  ) => _save(classificationRulesId, config.toFirestore());

  @override
  Future<Result<PrioritizationConfig>> getPrioritization() =>
      _get(prioritizationId, PrioritizationConfig.fromFirestore);

  @override
  Stream<Result<PrioritizationConfig>> watchPrioritization() =>
      _watch(prioritizationId, PrioritizationConfig.fromFirestore);

  @override
  Future<Result<void>> updatePrioritization(PrioritizationConfig config) =>
      _save(prioritizationId, config.toFirestore());

  @override
  Future<Result<DuplicateDetectionConfig>> getDuplicateDetection() =>
      _get(duplicateDetectionId, DuplicateDetectionConfig.fromFirestore);

  @override
  Stream<Result<DuplicateDetectionConfig>> watchDuplicateDetection() =>
      _watch(duplicateDetectionId, DuplicateDetectionConfig.fromFirestore);

  @override
  Future<Result<void>> updateDuplicateDetection(
    DuplicateDetectionConfig config,
  ) => _save(duplicateDetectionId, config.toFirestore());

  Future<Result<T>> _get<T>(String id, T Function(RowSnapshot) convert) =>
      guard.call(() async {
        final row = await client
            .from(_table)
            .select()
            .eq('id', id)
            .maybeSingle();
        if (row == null) throw SupabaseRepository.notFound('No config $id');
        return convert(RowSnapshot.fromConfigRow(row));
      });

  Stream<Result<T>> _watch<T>(String id, T Function(RowSnapshot) convert) =>
      guard.stream(
        client.from(_table).stream(primaryKey: const ['id']).eq('id', id).map((
          rows,
        ) {
          if (rows.isEmpty) throw SupabaseRepository.notFound('No config $id');
          return convert(RowSnapshot.fromConfigRow(rows.first));
        }),
      );

  /// The document without who saved it and when: the database stamps
  /// those itself.
  Future<Result<void>> _save(String id, Map<String, dynamic> document) =>
      rpc('update_config', {
        'id': id,
        'data': {...document}
          ..remove('updatedAt')
          ..remove('updatedBy'),
      });
}
