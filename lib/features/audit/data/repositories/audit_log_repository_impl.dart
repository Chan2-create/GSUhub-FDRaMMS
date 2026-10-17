import '../../../../core/data/supabase_repository.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../../core/utils/result.dart';
import '../models/audit_log_entry.dart';
import 'audit_log_repository.dart';

/// Supabase-backed [AuditLogRepository] (Objective 1).
///
/// Read-only here. Every entry is written by the database function that
/// makes the change it records, in the same transaction, under the
/// caller's own name; nobody can update or delete one (the table refuses
/// it, owner included). Administrators read them under row level security.
class AuditLogRepositoryImpl extends SupabaseRepository
    implements AuditLogRepository {
  const AuditLogRepositoryImpl({required super.client, required super.guard});

  static const String _table = 'audit_logs';

  /// Entries are not written on their own: one that recorded no change, or
  /// a change made some other way, would make the trail say something
  /// that did not happen.
  @override
  Future<Result<String>> record(AuditLogEntry entry) =>
      SupabaseRepository.unsupported('AuditLogRepository.record');

  @override
  Future<Result<List<AuditLogEntry>>> getForEntity({
    required String entityType,
    required String entityId,
    int limit = 50,
  }) => getMany(
    query: client
        .from(_table)
        .select()
        .eq('entity_type', entityType)
        .eq('entity_id', entityId)
        .order('timestamp')
        .limit(limit),
    convert: AuditLogEntry.fromFirestore,
  );

  @override
  Future<Result<List<AuditLogEntry>>> getForActor(
    String actorId, {
    int limit = 50,
  }) => getMany(
    query: client
        .from(_table)
        .select()
        .eq('actor_id', actorId)
        .order('timestamp')
        .limit(limit),
    convert: AuditLogEntry.fromFirestore,
  );

  @override
  Future<Result<List<AuditLogEntry>>> query({
    AuditAction? action,
    String? entityType,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) {
    var built = client.from(_table).select();
    if (action != null) built = built.eq('action', action.id);
    if (entityType != null) built = built.eq('entity_type', entityType);
    if (from != null) {
      built = built.gte('timestamp', SupabaseRepository.time(from)!);
    }
    if (to != null) {
      built = built.lte('timestamp', SupabaseRepository.time(to)!);
    }
    return getMany(
      query: built.order('timestamp').limit(limit),
      convert: AuditLogEntry.fromFirestore,
    );
  }
}
