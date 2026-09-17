import '../../../../core/enums/audit_action.dart';
import '../../../../core/utils/result.dart';
import '../models/audit_log_entry.dart';

/// Abstract contract for the append-only `audit_logs` collection
/// (manuscript §3.4, Auditability).
///
/// Like the inventory ledger, the invariant is enforced by the shape of
/// this contract: there is **no update and no delete method**. An audit
/// trail that can be rewritten is not evidence of anything.
///
/// **Interface only** — implementation is 1.C.
abstract interface class AuditLogRepository {
  /// Appends an entry. The only write operation this contract offers.
  Future<Result<String>> record(AuditLogEntry entry);

  /// History for one document, e.g. every change to a given report.
  Future<Result<List<AuditLogEntry>>> getForEntity({
    required String entityType,
    required String entityId,
    int limit = 50,
  });

  /// Everything one user did — the "who changed this" question, asked from
  /// the other direction.
  Future<Result<List<AuditLogEntry>>> getForActor(
    String actorId, {
    int limit = 50,
  });

  /// Filtered query for the Admin activity view.
  Future<Result<List<AuditLogEntry>>> query({
    AuditAction? action,
    String? entityType,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  });
}
