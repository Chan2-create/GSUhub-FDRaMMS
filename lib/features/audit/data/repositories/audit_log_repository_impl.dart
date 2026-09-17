import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../../core/utils/result.dart';
import '../models/audit_log_entry.dart';
import 'audit_log_repository.dart';

/// Firestore-backed [AuditLogRepository].
///
/// Append-only: this class offers no update or delete path, matching the
/// contract and the security rules. The absence is the enforcement.
class AuditLogRepositoryImpl extends FirestoreRepository
    implements AuditLogRepository {
  const AuditLogRepositoryImpl({required super.db, required super.guard});

  static const String _path = FirestorePaths.auditLogs;

  @override
  Future<Result<String>> record(AuditLogEntry entry) =>
      add(path: _path, data: entry.toFirestore());

  @override
  Future<Result<List<AuditLogEntry>>> getForEntity({
    required String entityType,
    required String entityId,
    int limit = 50,
  }) => getMany(
    query: collection(_path)
        .where('entityType', isEqualTo: entityType)
        .where('entityId', isEqualTo: entityId)
        .orderBy('timestamp', descending: true)
        .limit(limit),
    convert: AuditLogEntry.fromFirestore,
  );

  @override
  Future<Result<List<AuditLogEntry>>> getForActor(
    String actorId, {
    int limit = 50,
  }) => getMany(
    query: collection(_path)
        .where('actorId', isEqualTo: actorId)
        .orderBy('timestamp', descending: true)
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
    Query<Map<String, dynamic>> built = collection(_path);

    if (action != null) built = built.where('action', isEqualTo: action.id);
    if (entityType != null) {
      built = built.where('entityType', isEqualTo: entityType);
    }
    if (from != null) {
      built = built.where(
        'timestamp',
        isGreaterThanOrEqualTo: Timestamp.fromDate(from.toUtc()),
      );
    }
    if (to != null) {
      built = built.where(
        'timestamp',
        isLessThanOrEqualTo: Timestamp.fromDate(to.toUtc()),
      );
    }

    return getMany(
      query: built.orderBy('timestamp', descending: true).limit(limit),
      convert: AuditLogEntry.fromFirestore,
    );
  }
}
