import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/models/status_change.dart';

import '../support/fake_requestor_app.dart';

/// The requestor's report detail with its status timeline (Figma
/// `169:1355`, Objective 3.B), inside the real app and router.
void main() {
  const id = 'rep-0042';
  final filed = DateTime.now().subtract(const Duration(days: 3));

  StatusChange change(
    ReportStatus status,
    int hoursAfterFiling, {
    String? note,
    String? personnelName,
    DamageCategory? trade,
  }) => StatusChange(
    id: '${status.name}-$hoursAfterFiling',
    status: status,
    changedAt: filed.add(Duration(hours: hoursAfterFiling)),
    changedBy: 'admin-1',
    note: note,
    personnelName: personnelName,
    personnelSpecialization: trade,
  );

  /// The report at [status], as its history would have brought it there.
  DamageReport report(
    ReportStatus status, {
    DamageCategory? category,
    PriorityLevel? officialPriority,
    String? reviewedBy,
    String? workOrderId,
    String? rejectionReason,
    String? duplicateOf,
  }) => fakeMyReport(
    id,
    status: status,
    title: 'Leaking pipe under sink',
    location: 'Science Building, Laboratory 3',
    submittedAt: filed,
    category: category,
    officialPriority: officialPriority,
    reviewedBy: reviewedBy,
    workOrderId: workOrderId,
    rejectionReason: rejectionReason,
    duplicateOf: duplicateOf,
  );

  Future<RequestorHarness> open(
    WidgetTester tester,
    DamageReport report, {
    List<StatusChange> history = const [],
  }) async {
    final app = RequestorHarness(reports: [report]);
    for (final entry in history) {
      app.reports.record(report.id, entry);
    }
    await app.pump(tester, start: RoutePaths.staffReportDetailFor(report.id));
    return app;
  }

  testWidgets('a new report: its number, Pending, step one, awaiting review', (
    tester,
  ) async {
    await open(
      tester,
      report(ReportStatus.submitted),
      history: [change(ReportStatus.submitted, 0)],
    );

    expect(find.text('Report Details'), findsOneWidget);
    expect(find.text('#REP-0042'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Your Report'), findsOneWidget);
    expect(find.text('Leaking pipe under sink'), findsOneWidget);
    expect(find.text('Science Building'), findsOneWidget);
    expect(find.text('Laboratory 3'), findsOneWidget);
    expect(find.text('AWAITING REVIEW'), findsOneWidget);
    expect(find.text('Report received'), findsOneWidget);
    expect(find.text('Assigned Maintenance Personnel'), findsNothing);
    expect(find.text('Rate this Service'), findsNothing);
    // What they filed is still there.
    expect(
      find.text('The fan wobbles and sparks at the switch.'),
      findsOneWidget,
    );
    expect(find.text('DAMAGE TYPE YOU SUGGESTED'), findsOneWidget);
  });

  testWidgets(
    'the official priority and type show only once GSU sets them, and the '
    "requestor's suggestion never stands in for them",
    (tester) async {
      // Classified (by the keyword classifier, say) but not yet reviewed.
      final app = await open(
        tester,
        report(ReportStatus.underReview, category: DamageCategory.plumbing),
      );

      expect(find.text('AWAITING REVIEW'), findsOneWidget);
      expect(find.text('Plumbing'), findsNothing);
      // Their own suggestion appears only as theirs.
      expect(find.text('Electrical'), findsOneWidget);
      expect(find.text('DAMAGE TYPE YOU SUGGESTED'), findsOneWidget);

      app.reports.put(
        report(
          ReportStatus.approved,
          category: DamageCategory.plumbing,
          officialPriority: PriorityLevel.high,
          reviewedBy: 'admin-1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AWAITING REVIEW'), findsNothing);
      expect(find.text('HIGH PRIORITY'), findsOneWidget);
      expect(find.text('Plumbing'), findsOneWidget);
    },
  );

  testWidgets('once assigned it reads as the work order, naming who', (
    tester,
  ) async {
    await open(
      tester,
      report(
        ReportStatus.assigned,
        workOrderId: 'wo-0007',
        reviewedBy: 'admin-1',
      ),
      history: [
        change(ReportStatus.submitted, 0),
        change(ReportStatus.underReview, 1),
        change(ReportStatus.approved, 2),
        change(
          ReportStatus.assigned,
          6,
          personnelName: 'Juan Luna',
          trade: DamageCategory.plumbing,
        ),
      ],
    );

    expect(find.text('Work Order Details'), findsOneWidget);
    expect(find.text('#WO-0007'), findsOneWidget);
    expect(find.text('Linked Report'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Assigned Maintenance Personnel'), findsOneWidget);
    expect(find.text('Juan Luna'), findsOneWidget);
    expect(find.text('PLUMBING'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Assigned [A-Z][a-z]{2} \d')),
      findsOne,
    );

    // Newest first.
    final order = [
      'Personnel assigned: Juan Luna',
      'Approved',
      'Under review',
      'Report received',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        tester.getTopLeft(find.text(order[i - 1])).dy,
        lessThan(tester.getTopLeft(find.text(order[i])).dy),
        reason: '${order[i - 1]} above ${order[i]}',
      );
    }
  });

  group('every status reads in plain words on the timeline', () {
    for (final status in ReportStatus.values) {
      testWidgets('${status.name}: "${status.timelineLabel}"', (tester) async {
        await open(
          tester,
          report(status),
          history: [
            change(ReportStatus.submitted, 0),
            if (status != ReportStatus.submitted) change(status, 5),
          ],
        );

        expect(find.textContaining(status.timelineLabel), findsWidgets);
        // Never the enum's own name, nor the console's capitals as a step.
        expect(find.text(status.name), findsNothing);
        if (status != ReportStatus.submitted) {
          expect(find.text('Report received'), findsOneWidget);
        }
      });
    }
  });

  testWidgets("an administrator's move reaches the open page by itself", (
    tester,
  ) async {
    final app = await open(
      tester,
      report(ReportStatus.submitted),
      history: [change(ReportStatus.submitted, 0)],
    );
    expect(find.text('Under review'), findsNothing);

    // The report and its history entry, as one transaction lands them.
    app.reports
      ..put(report(ReportStatus.underReview))
      ..record(id, change(ReportStatus.underReview, 1));
    await tester.pumpAndSettle();
    expect(find.text('Under review'), findsOneWidget);

    app.reports
      ..put(
        report(
          ReportStatus.assigned,
          workOrderId: 'wo-0007',
          reviewedBy: 'admin-1',
        ),
      )
      ..record(id, change(ReportStatus.approved, 2))
      ..record(
        id,
        change(ReportStatus.assigned, 3, personnelName: 'Juan Luna'),
      );
    await tester.pumpAndSettle();

    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Juan Luna'), findsOneWidget);
    expect(find.text('#WO-0007'), findsOneWidget);
  });

  testWidgets('a rejected report says so, with the reason', (tester) async {
    await open(
      tester,
      report(
        ReportStatus.rejected,
        reviewedBy: 'admin-1',
        rejectionReason: 'Outside GSU scope.',
      ),
      history: [
        change(ReportStatus.submitted, 0),
        change(ReportStatus.underReview, 1),
        change(ReportStatus.rejected, 2, note: 'Outside GSU scope.'),
      ],
    );

    // At the top, in place of the steps, and on the timeline.
    expect(find.text('NOT ACCEPTED'), findsNWidgets(2));
    expect(find.text('"Outside GSU scope."'), findsNWidgets(2));
    expect(find.text('Active'), findsNothing);
    expect(find.text('Rate this Service'), findsNothing);
    // GSU has decided; there is no review left to await, and no type of
    // its own to show.
    expect(find.text('AWAITING REVIEW'), findsNothing);
  });

  testWidgets('a merged report says where it is tracked now', (tester) async {
    await open(
      tester,
      report(ReportStatus.merged, duplicateOf: 'rep-0001'),
      history: [
        change(ReportStatus.submitted, 0),
        change(ReportStatus.merged, 2),
      ],
    );

    expect(find.textContaining('#REP-0001'), findsNWidgets(2));
    expect(find.text('Merged with an existing report (#REP-0001)'), findsOne);
  });

  testWidgets('a completed report offers to rate the service', (tester) async {
    await open(
      tester,
      report(ReportStatus.completed, reviewedBy: 'admin-1'),
      history: [
        change(ReportStatus.submitted, 0),
        change(ReportStatus.completed, 40),
      ],
    );

    expect(find.text('Completed'), findsWidgets);
    final rate = find.text('Rate this Service');
    await tester.ensureVisible(rate);
    await tester.pumpAndSettle();
    await tester.tap(rate);
    await tester.pump();

    // The rating itself is Objective 3.C's.
    expect(find.textContaining('Objective 3.C'), findsOneWidget);
  });

  testWidgets('a report filed before 3.B still shows when it was filed', (
    tester,
  ) async {
    await open(tester, report(ReportStatus.approved, reviewedBy: 'admin-1'));

    expect(find.text('Report received'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('a failed history read says so and can be retried', (
    tester,
  ) async {
    final app = RequestorHarness(reports: [report(ReportStatus.submitted)]);
    app.reports.historyFailure = const NetworkFailure(
      'Cannot reach the server.',
    );
    await app.pump(tester, start: RoutePaths.staffReportDetailFor(id));

    expect(find.textContaining('Cannot reach the server.'), findsOneWidget);
    // The report itself still shows.
    expect(find.text('#REP-0042'), findsOneWidget);

    app.reports.historyFailure = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Report received'), findsOneWidget);
  });

  testWidgets('the listeners close when the page is left', (tester) async {
    final app = await open(tester, report(ReportStatus.submitted));
    expect(app.reports.openListeners, 2);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Back on My Reports: only its own listener is left.
    expect(currentPath(tester), RoutePaths.staffMyReports);
    expect(app.reports.openListeners, 1);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
