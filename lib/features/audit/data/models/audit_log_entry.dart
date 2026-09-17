import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/enums/audit_action.dart';
import '../../../../core/utils/firestore_converters.dart';

/// An `audit_logs` document — one recorded state change, satisfying
/// manuscript §3.4's Auditability requirement: "The system shall record
/// major user activities such as report submissions, task assignments,
/// status updates, and work order completion for monitoring and
/// accountability purposes."
///
/// **Append-only**, for the same reason as `inventory_transactions`: an
/// audit trail that can be edited is not an audit trail. Enforced by the
/// absence of any update/delete path in the repository contract and by
/// security rules that permit `create` only.
///
/// Unlike the ledger, this model *does* keep `copyWith` off as well — see
/// the note above [toFirestore].
///
/// The `audit` feature module is new in 1.B; 1.A's feature directories did
/// not include one because auditing is cross-cutting rather than
/// user-facing.
class AuditLogEntry {
  AuditLogEntry({
    required this.id,
    required this.actorId,
    required this.actorName,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.description,
    required this.timestamp,
    this.changes,
  }) {
    FirestoreConverters.validateNotBlank(actorId, 'actorId');
    FirestoreConverters.validateNotBlank(entityType, 'entityType');
    FirestoreConverters.validateNotBlank(entityId, 'entityId');
    FirestoreConverters.validateNotBlank(description, 'description');
  }

  factory AuditLogEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return AuditLogEntry(
      id: doc.id,
      actorId: FirestoreConverters.require<String>(data, 'actorId'),
      actorName: FirestoreConverters.require<String>(data, 'actorName'),
      action: FirestoreConverters.requireEnum(
        data,
        'action',
        AuditAction.fromId,
      ),
      entityType: FirestoreConverters.require<String>(data, 'entityType'),
      entityId: FirestoreConverters.require<String>(data, 'entityId'),
      description: FirestoreConverters.require<String>(data, 'description'),
      changes: FirestoreConverters.optional<Map<String, dynamic>>(
        data,
        'changes',
      ),
      timestamp: FirestoreConverters.requireDate(data, 'timestamp'),
    );
  }

  final String id;

  /// The `users` document that performed the action.
  final String actorId;

  /// DENORMALIZED from `users.fullName` — an audit entry must remain
  /// legible even if the account is later renamed or deactivated, which is
  /// precisely when someone is most likely to be reading it.
  final String actorName;

  final AuditAction action;

  /// Collection name of the affected document — a value from
  /// `FirestorePaths`.
  final String entityType;

  final String entityId;

  /// Human-readable summary, e.g. "Official priority changed from High to
  /// Critical".
  final String description;

  /// Optional before/after field values. Free-form because the shape
  /// differs per entity; kept small deliberately — this is a change log,
  /// not a document-version store.
  final Map<String, dynamic>? changes;

  final DateTime timestamp;

  // Intentionally no copyWith — an audit entry is immutable once written.
  Map<String, dynamic> toFirestore() => {
    'actorId': actorId,
    'actorName': actorName,
    'action': action.id,
    'entityType': entityType,
    'entityId': entityId,
    'description': description,
    'changes': changes,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditLogEntry &&
          other.id == id &&
          other.actorId == actorId &&
          other.actorName == actorName &&
          other.action == action &&
          other.entityType == entityType &&
          other.entityId == entityId &&
          other.description == description &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    id,
    actorId,
    actorName,
    action,
    entityType,
    entityId,
    description,
    timestamp,
  );

  @override
  String toString() =>
      'AuditLogEntry(id: $id, actor: $actorName, action: $action, '
      '$entityType/$entityId)';
}
