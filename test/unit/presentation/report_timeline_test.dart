import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/features/reporting/data/models/status_change.dart';
import 'package:gsuhub/features/reporting/presentation/my_reports/report_timeline.dart';

import '../../support/fake_requestor_app.dart';

/// The requestor's progress timeline (Objective 3.B), built from a report
/// and its status history.
void main() {
  final filed = DateTime.utc(2026, 9, 20, 8);

  StatusChange change(
    ReportStatus status,
    int hoursAfterFiling, {
    String? note,
    String? personnelName,
  }) => StatusChange(
    id: '${status.name}-$hoursAfterFiling',
    status: status,
    changedAt: filed.add(Duration(hours: hoursAfterFiling)),
    changedBy: 'admin-1',
    note: note,
    personnelName: personnelName,
    personnelSpecialization: personnelName == null
        ? null
        : DamageCategory.plumbing,
  );

  List<ReportStatus> statusesOf(ReportTimeline timeline) => [
    for (final entry in timeline.entries) entry.status,
  ];

  test('lists every recorded step, newest first', () {
    final report = fakeMyReport(
      'r1',
      status: ReportStatus.inProgress,
      submittedAt: filed,
    );

    final timeline = ReportTimeline.of(report, [
      change(ReportStatus.approved, 2),
      change(ReportStatus.submitted, 0),
      change(ReportStatus.inProgress, 30),
      change(ReportStatus.underReview, 1),
      change(ReportStatus.assigned, 6, personnelName: 'Juan Luna'),
    ]);

    expect(statusesOf(timeline), [
      ReportStatus.inProgress,
      ReportStatus.assigned,
      ReportStatus.approved,
      ReportStatus.underReview,
      ReportStatus.submitted,
    ]);
    expect(timeline.entries.first.at, filed.add(const Duration(hours: 30)));
  });

  test('names who the report was last assigned to', () {
    final report = fakeMyReport('r1', status: ReportStatus.assigned);

    final timeline = ReportTimeline.of(report, [
      change(ReportStatus.submitted, 0),
      change(ReportStatus.assigned, 6, personnelName: 'Juan Luna'),
    ]);

    expect(timeline.assignment?.personnelName, 'Juan Luna');
    expect(
      timeline.assignment?.personnelSpecialization,
      DamageCategory.plumbing,
    );
  });

  test('has no assignment before the report is assigned', () {
    final report = fakeMyReport('r1', status: ReportStatus.approved);

    final timeline = ReportTimeline.of(report, [
      change(ReportStatus.submitted, 0),
      change(ReportStatus.approved, 2),
    ]);

    expect(timeline.assignment, isNull);
  });

  test('a report with no history still shows when it was filed', () {
    // Filed before 3.B, and never moved since.
    final report = fakeMyReport('r1', submittedAt: filed);

    final timeline = ReportTimeline.of(report, const []);

    expect(statusesOf(timeline), [ReportStatus.submitted]);
    expect(timeline.entries.single.at, filed);
  });

  test('a current status the history has not reached is still shown', () {
    // Moved to rejected before 3.B wrote any history.
    final report = fakeMyReport(
      'r1',
      status: ReportStatus.rejected,
      submittedAt: filed,
      rejectionReason: 'Outside GSU scope.',
    );

    final timeline = ReportTimeline.of(report, const []);

    expect(statusesOf(timeline), [
      ReportStatus.rejected,
      ReportStatus.submitted,
    ]);
    expect(timeline.entries.first.at, report.updatedAt);
    expect(timeline.entries.first.note, 'Outside GSU scope.');
  });

  test('a history begun after filing gains the filing', () {
    final report = fakeMyReport(
      'r1',
      status: ReportStatus.approved,
      submittedAt: filed,
    );

    final timeline = ReportTimeline.of(report, [
      change(ReportStatus.approved, 2),
    ]);

    expect(statusesOf(timeline), [
      ReportStatus.approved,
      ReportStatus.submitted,
    ]);
  });

  test('every status has its own plain timeline wording', () {
    final labels = {
      for (final status in ReportStatus.values) status.timelineLabel,
    };
    expect(labels, hasLength(ReportStatus.values.length));
    for (final status in ReportStatus.values) {
      expect(status.timelineLabel, isNot(status.name), reason: '$status');
      expect(status.timelineLabel, isNot(status.label), reason: '$status');
    }
  });
}
