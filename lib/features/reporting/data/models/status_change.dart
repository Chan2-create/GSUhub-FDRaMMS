import '../../../../core/constants/damage_categories.dart';
import '../../../../core/data/data_record.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/record_converters.dart';

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
    RecordConverters.validateNotBlank(changedBy, 'changedBy');
  }

  factory StatusChange.fromRecord(DataRecord record) {
    final data = record.fields;
    return StatusChange(
      id: record.id,
      status: RecordConverters.requireEnum(data, 'status', ReportStatus.fromId),
      changedAt: RecordConverters.requireDate(data, 'changedAt'),
      changedBy: RecordConverters.require<String>(data, 'changedBy'),
      note: RecordConverters.optional<String>(data, 'note'),
      personnelName: RecordConverters.optional<String>(data, 'personnelName'),
      personnelSpecialization: RecordConverters.optionalEnum(
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

  Map<String, dynamic> toFields() => {
    'status': status.id,
    'changedAt': changedAt,
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
