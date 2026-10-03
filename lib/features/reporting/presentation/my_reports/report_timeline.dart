import 'package:flutter/foundation.dart';

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/report_status.dart';
import '../../data/models/damage_report.dart';
import '../../data/models/status_change.dart';

/// One step on the requestor's progress timeline (Objective 3.B).
@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.status,
    required this.at,
    this.note,
    this.personnelName,
    this.personnelSpecialization,
  });

  factory TimelineEntry.of(StatusChange change) => TimelineEntry(
    status: change.status,
    at: change.changedAt,
    note: change.note,
    personnelName: change.personnelName,
    personnelSpecialization: change.personnelSpecialization,
  );

  final ReportStatus status;
  final DateTime at;

  /// The administrator's reason, on a rejection.
  final String? note;

  /// Who will do the work, on an assignment.
  final String? personnelName;
  final DamageCategory? personnelSpecialization;

  @override
  bool operator ==(Object other) =>
      other is TimelineEntry &&
      other.status == status &&
      other.at == at &&
      other.note == note &&
      other.personnelName == personnelName &&
      other.personnelSpecialization == personnelSpecialization;

  @override
  int get hashCode =>
      Object.hash(status, at, note, personnelName, personnelSpecialization);

  @override
  String toString() => 'TimelineEntry($status at $at)';
}

/// A report's progress as the requestor sees it: its status history,
/// newest first, and who it was assigned to.
///
/// Built from the report as well as its history, so it holds up where the
/// history is incomplete. Reports filed before 3.B have no history at all,
/// and a report moved before 3.B has entries only from then on: the filing
/// is taken from `submittedAt`, and a current status the history has not
/// reached from `updatedAt` — the server time the move itself was stamped
/// with, so it reads the same as the entry that would have recorded it.
@immutable
class ReportTimeline {
  const ReportTimeline._({required this.entries, required this.assignment});

  factory ReportTimeline.of(DamageReport report, List<StatusChange> history) {
    final steps = [for (final change in history) TimelineEntry.of(change)]
      ..sort((a, b) => a.at.compareTo(b.at));

    if (steps.isEmpty || steps.first.status != ReportStatus.submitted) {
      steps.insert(
        0,
        TimelineEntry(status: ReportStatus.submitted, at: report.submittedAt),
      );
    }
    if (steps.last.status != report.status) {
      steps.add(
        TimelineEntry(
          status: report.status,
          at: report.updatedAt,
          note: report.status == ReportStatus.rejected
              ? report.rejectionReason
              : null,
        ),
      );
    }

    final newestFirst = steps.reversed.toList(growable: false);
    return ReportTimeline._(
      entries: newestFirst,
      assignment: newestFirst
          .where((entry) => entry.status == ReportStatus.assigned)
          .firstOrNull,
    );
  }

  /// Every step, newest first, as the design's timeline runs (Figma
  /// `169:1064`).
  final List<TimelineEntry> entries;

  /// The latest assignment, for the "Assigned Maintenance Personnel" card
  /// (Figma `169:1048`) — null until the report is assigned.
  final TimelineEntry? assignment;
}
