import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/firestore_converters.dart';

/// One step of a report's progress: an entry of
/// `damage_reports/{reportId}/status_history` (Objective 3.B).
///
/// Written in the same transaction as the status change it records, so the
/// requestor's timeline cannot disagree with the report. The same moves are
/// in `audit_logs`, but requestors cannot read those, and a work order's
/// moves are logged against the work order rather than the report.
///
/// DERIVED — the manuscript asks for "real-time status monitoring" (§1.5)
/// without saying how progress is stored. See docs/data_dictionary.md.
class StatusChange {
  StatusChange({
    required this.id,
    required this.status,
    required this.changedAt,
    required this.changedBy,
    this.note,
    this.personnelName,
    this.personnelSpecialization,
  }) {
    FirestoreConverters.validateNotBlank(changedBy, 'changedBy');
  }

  factory StatusChange.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return StatusChange(
      id: doc.id,
      status: FirestoreConverters.requireEnum(
        data,
        'status',
        ReportStatus.fromId,
      ),
      changedAt: FirestoreConverters.requireDate(data, 'changedAt'),
      changedBy: FirestoreConverters.require<String>(data, 'changedBy'),
      note: FirestoreConverters.optional<String>(data, 'note'),
      personnelName: FirestoreConverters.optional<String>(
        data,
        'personnelName',
      ),
      personnelSpecialization: FirestoreConverters.optionalEnum(
        data,
        'personnelSpecialization',
        DamageCategory.fromId,
      ),
    );
  }

  final String id;

  /// The status the report moved to.
  final ReportStatus status;

  /// Server time of the move.
  final DateTime changedAt;

  /// The uid of whoever made the move. The rules require it to be the
  /// writer.
  final String changedBy;

  /// What the requestor is told beyond the status itself: the reason a
  /// report was rejected.
  final String? note;

  /// Who will do the work, on an `assigned` entry. Kept here because a
  /// requestor cannot read other people's accounts or the work order, and
  /// the detail screen names the assigned personnel (Figma `169:1048`).
  final String? personnelName;

  /// That person's trade, on an `assigned` entry.
  final DamageCategory? personnelSpecialization;

  Map<String, dynamic> toFirestore() => {
    'status': status.id,
    'changedAt': Timestamp.fromDate(changedAt),
    'changedBy': changedBy,
    'note': note,
    'personnelName': personnelName,
    'personnelSpecialization': personnelSpecialization?.id,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatusChange &&
          other.id == id &&
          other.status == status &&
          other.changedAt == changedAt &&
          other.changedBy == changedBy &&
          other.note == note &&
          other.personnelName == personnelName &&
          other.personnelSpecialization == personnelSpecialization;

  @override
  int get hashCode => Object.hash(
    id,
    status,
    changedAt,
    changedBy,
    note,
    personnelName,
    personnelSpecialization,
  );

  @override
  String toString() =>
      'StatusChange(id: $id, status: $status, changedAt: $changedAt)';
}
