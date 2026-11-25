import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/damage_reports/data/models/status_change.dart';
import 'package:intl/intl.dart';

import '../support/fake_requestor_app.dart';

/// What the requestor reads on the phone (2026-11-26, the adviser's
/// consultation): a report under review says so, not "Pending", and one
/// GSU rescheduled shows the new date and the reason, on the report and on
/// its timeline.
void main() {
  final filed = DateTime.now().subtract(const Duration(days: 2));

  testWidgets('a report under review reads Under Review, not Pending', (
    tester,
  ) async {
    final report = fakeMyReport(
      'rep-7',
      status: ReportStatus.underReview,
      submittedAt: filed,
    );
    final app = RequestorHarness(reports: [report]);
    await app.pump(tester, start: RoutePaths.staffReportDetailFor('rep-7'));

    expect(find.text('Under Review'), findsWidgets);
    expect(find.text('Pending'), findsNothing);
  });

  testWidgets('My Reports lists it as Under Review too', (tester) async {
    final app = RequestorHarness(
      reports: [
        fakeMyReport(
          'rep-7',
          status: ReportStatus.underReview,
          submittedAt: filed,
        ),
      ],
    );
    await app.pump(tester, start: RoutePaths.staffMyReports);

    expect(find.text('Under Review'), findsOneWidget);
  });

  testWidgets('a rescheduled report shows the new date and the reason', (
    tester,
  ) async {
    final moved = DateTime.now().add(const Duration(days: 4));
    final report =
        fakeMyReport(
          'rep-8',
          status: ReportStatus.approved,
          submittedAt: filed,
          category: DamageCategory.electrical,
          officialPriority: PriorityLevel.high,
          reviewedBy: 'admin-1',
        ).copyWith(
          rescheduledTo: moved,
          rescheduleReason: 'The only electrician is on leave.',
        );
    final app = RequestorHarness(reports: [report]);
    app.reports.record(
      'rep-8',
      StatusChange(
        id: 'h-moved',
        status: ReportStatus.approved,
        changedAt: DateTime.now().subtract(const Duration(hours: 1)),
        changedBy: 'admin-1',
        note: 'The only electrician is on leave.',
        rescheduledTo: moved,
      ),
    );
    await app.pump(tester, start: RoutePaths.staffReportDetailFor('rep-8'));

    expect(find.text('Rescheduled'), findsOneWidget);
    final day = DateFormat('EEE, MMM d, y').format(moved);
    expect(find.text('RESCHEDULED TO ${day.toUpperCase()}'), findsOneWidget);
    expect(
      find.text('"The only electrician is on leave."'),
      findsAtLeastNWidgets(1),
    );
    // On the timeline too.
    final short = DateFormat('MMM d, y').format(moved);
    expect(find.text('RESCHEDULED TO ${short.toUpperCase()}'), findsOneWidget);
  });
}
