import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/presentation/my_reports/my_reports_providers.dart';

/// The faculty and staff app's view of its own reports (Objective 3.A):
/// the three stages, the home screen's counts, and My Reports' filter and
/// search.
void main() {
  DamageReport report(
    String id,
    ReportStatus status, {
    String title = 'Broken fan',
    String location = 'Science Building, Laboratory 1',
    DamageCategory? requestorCategory,
  }) => DamageReport(
    id: id,
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: title,
    description: 'The ceiling fan wobbles.',
    requestorPriority: PriorityLevel.medium,
    requestorCategory: requestorCategory,
    status: status,
    locationDescription: location,
    submittedAt: DateTime.utc(2026, 9),
    updatedAt: DateTime.utc(2026, 9),
  );

  group('ReportStatus.progress', () {
    test('collapses the eleven statuses into the stages a requestor sees', () {
      expect(
        {for (final status in ReportStatus.values) status: status.progress},
        {
          ReportStatus.submitted: ReportProgress.pending,
          ReportStatus.underReview: ReportProgress.pending,
          ReportStatus.approved: ReportProgress.inProgress,
          ReportStatus.assigned: ReportProgress.inProgress,
          ReportStatus.inProgress: ReportProgress.inProgress,
          ReportStatus.forReview: ReportProgress.inProgress,
          ReportStatus.completed: ReportProgress.completed,
          ReportStatus.closed: ReportProgress.completed,
          ReportStatus.merged: ReportProgress.closedOut,
          ReportStatus.rejected: ReportProgress.closedOut,
          ReportStatus.archived: ReportProgress.closedOut,
        },
      );
    });
  });

  group('ReportOverview', () {
    test('counts each stage, leaving out reports that ended unworked', () {
      final overview = ReportOverview.of([
        report('a', ReportStatus.submitted),
        report('b', ReportStatus.underReview),
        report('c', ReportStatus.assigned),
        report('d', ReportStatus.completed),
        report('e', ReportStatus.closed),
        report('f', ReportStatus.rejected),
      ]);

      expect(overview.active, 2);
      expect(overview.inProgress, 1);
      expect(overview.completed, 2);
      expect(overview.summary, '2 Active • 1 In-Progress • 2 Completed');
    });

    test('an empty history is all zeroes', () {
      expect(
        ReportOverview.of(const []).summary,
        '0 Active • 0 In-Progress • 0 Completed',
      );
    });
  });

  group('MyReportsView', () {
    final reports = [
      report('a', ReportStatus.submitted, location: 'Main Library, Level 2'),
      report(
        'b',
        ReportStatus.inProgress,
        title: 'Leaking pipe',
        requestorCategory: DamageCategory.plumbing,
      ),
      report('c', ReportStatus.completed),
      report('d', ReportStatus.merged),
    ];

    List<String> shown(MyReportsView view) => [
      for (final report in reports.where(view.matches)) report.id,
    ];

    test('All shows everything, including reports that ended unworked', () {
      expect(shown(const MyReportsView()), ['a', 'b', 'c', 'd']);
    });

    test('a stage filter shows that stage only', () {
      expect(shown(const MyReportsView(progress: ReportProgress.pending)), [
        'a',
      ]);
      expect(shown(const MyReportsView(progress: ReportProgress.completed)), [
        'c',
      ]);
    });

    test('the search matches location, title and damage type', () {
      expect(shown(const MyReportsView(search: 'library')), ['a']);
      expect(shown(const MyReportsView(search: 'LEAK')), ['b']);
      expect(shown(const MyReportsView(search: 'plumbing')), ['b']);
      expect(shown(const MyReportsView(search: 'nothing like it')), isEmpty);
    });

    test('search and filter apply together', () {
      expect(
        shown(
          const MyReportsView(progress: ReportProgress.pending, search: 'leak'),
        ),
        isEmpty,
      );
    });
  });
}
