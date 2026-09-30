import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/audit_action.dart';
import '../models/audit_actor.dart';
import '../models/audit_log_entry.dart';

/// Stages an `audit_logs` entry inside another repository's transaction.
///
/// The append-only [AuditLogRepository] records entries on their own; this
/// exists for the other case — a lifecycle change and its audit record
/// that must commit together or not at all. Writing the entry separately
/// after the change would leave a window where the change is saved and
/// the record is lost.
///
/// The entry is built through [AuditLogEntry] so its validation and field
/// names stay the single definition, then stamped with server time: a
/// device with a wrong clock would otherwise misorder the trail.
void stageAuditEntry(
  Transaction transaction,
  FirebaseFirestore firestore, {
  required AuditActor actor,
  required AuditAction action,
  required String entityType,
  required String entityId,
  required String description,
  Map<String, dynamic>? changes,
}) {
  final entry = AuditLogEntry(
    id: 'pending',
    actorId: actor.id,
    actorName: actor.name,
    action: action,
    entityType: entityType,
    entityId: entityId,
    description: description,
    timestamp: DateTime.now().toUtc(),
    changes: changes,
  );

  transaction.set(firestore.collection(FirestorePaths.auditLogs).doc(), {
    ...entry.toFirestore(),
    'timestamp': FirestoreRepository.serverNow,
  });
}
