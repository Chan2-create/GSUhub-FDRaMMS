import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/feedback/data/models/service_feedback.dart';
import 'package:gsuhub/features/reporting/data/models/status_change.dart';

import '../support/fake_requestor_app.dart';

/// The Ratings screen (Figma 169:1797, Objective 3.C): three star rows,
/// comments, Submit Rating and Skip, over the finished job.
void main() {
  const id = 'rep-0042';
  final finishedAt = DateTime.now().subtract(const Duration(hours: 2));

  RequestorHarness completedJob({
    ReportStatus status = ReportStatus.completed,
  }) {
    final app = RequestorHarness(
      reports: [
        fakeMyReport(
          id,
          status: status,
          location: 'Engineering Building, Room 302',
          category: DamageCategory.airConditioning,
          reviewedBy: 'admin-1',
          workOrderId: 'wo-0042',
        ).copyWith(facilityName: 'Engineering Building'),
      ],
    );
    app.reports.record(
      id,
      StatusChange(
        id: 'h1',
        status: ReportStatus.assigned,
        changedAt: finishedAt.subtract(const Duration(days: 1)),
        changedBy: 'admin-1',
        personnelName: 'Roberto Mendoza',
        personnelSpecialization: DamageCategory.electrical,
      ),
    );
    return app;
  }

  Future<void> open(WidgetTester tester, RequestorHarness app) async {
    await app.pump(tester, start: RoutePaths.staffRateReportFor(id));
  }

  /// Scrolls [target] to the middle of the screen and taps it. Scrolled
  /// only just into view it can sit under the floating bottom bar, which
  /// would take the tap.
  Future<void> tapInView(WidgetTester tester, Finder target) async {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapStar(WidgetTester tester, String dimension, int stars) =>
      tapInView(
        tester,
        find.bySemanticsLabel(RegExp('^$dimension: $stars of 5')),
      );

  Future<void> rateAll(WidgetTester tester) async {
    await tapStar(tester, 'Response time', 4);
    await tapStar(tester, 'Service quality', 5);
    await tapStar(tester, 'Overall satisfaction', 4);
  }

  Finder submit() => find.widgetWithText(FilledButton, 'Submit Rating');

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<FilledButton>(button).onPressed != null;

  testWidgets('shows the finished job, as drawn', (tester) async {
    await open(tester, completedJob());

    expect(find.text('Ratings'), findsOneWidget);
    expect(find.text('#WO-0042'), findsOneWidget);
    expect(find.text('Engineering Building'), findsOneWidget);
    expect(find.text('Room 302 • Air Conditioning'), findsOneWidget);
    expect(find.text('Roberto Mendoza'), findsOneWidget);
    expect(find.text('Electrical'), findsOneWidget);
    expect(find.text('How would you rate the service?'), findsOneWidget);
  });

  testWidgets('asks three questions and names each star count', (tester) async {
    await open(tester, completedJob());

    expect(find.text('Response time'), findsOneWidget);
    expect(find.text('Service quality'), findsOneWidget);
    expect(find.text('Overall satisfaction'), findsOneWidget);
    // Nothing is assumed: submitting waits for all three.
    expect(enabled(tester, submit()), isFalse);
    expect(find.text('Rate all three to submit.'), findsOneWidget);

    await tapStar(tester, 'Response time', 4);
    expect(find.text('Very Good'), findsOneWidget);
    await tapStar(tester, 'Service quality', 1);
    expect(find.text('Poor'), findsOneWidget);
    expect(enabled(tester, submit()), isFalse);

    await tapStar(tester, 'Overall satisfaction', 5);
    expect(find.text('Excellent'), findsOneWidget);
    expect(enabled(tester, submit()), isTrue);
    expect(find.text('Rate all three to submit.'), findsNothing);
  });

  testWidgets('submitting files the rating, closes the report and returns', (
    tester,
  ) async {
    final app = completedJob();
    await open(tester, app);
    await rateAll(tester);
    await tester.enterText(find.byType(TextField), '  Fixed the same day. ');

    await tapInView(tester, submit());
    await tester.pumpAndSettle();

    expect(app.feedback.rated.single.reportId, id);
    expect(app.feedback.rated.single.raterId, fakeRequestor.uid);
    expect(app.feedback.rated.single.comments, 'Fixed the same day.');
    expect(app.reports.byId(id)?.status, ReportStatus.closed);
    expect(find.textContaining('Your rating was sent'), findsOneWidget);
    // Back on the report, which now shows what was given.
    expect(currentPath(tester), RoutePaths.staffReportDetailFor(id));
  });

  testWidgets('a failed submission says why and keeps the stars', (
    tester,
  ) async {
    final app = completedJob();
    app.feedback.rateFailure = const NetworkFailure('Cannot reach the server.');
    await open(tester, app);
    await rateAll(tester);

    await tapInView(tester, submit());
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server.'), findsOneWidget);
    expect(find.text('Very Good'), findsNWidgets(2));
    expect(enabled(tester, submit()), isTrue);
    expect(app.reports.byId(id)?.status, ReportStatus.completed);
  });

  testWidgets('Skip leaves the report completed and rateable later', (
    tester,
  ) async {
    final app = completedJob();
    await open(tester, app);

    final skip = find.text('Skip');
    await tapInView(tester, skip);
    await tester.pumpAndSettle();

    expect(app.feedback.rated, isEmpty);
    expect(app.reports.byId(id)?.status, ReportStatus.completed);
    expect(currentPath(tester), RoutePaths.staffReportDetailFor(id));
    expect(find.text('Rate this Service'), findsOneWidget);
  });

  testWidgets('a report already rated shows what was given', (tester) async {
    final app = completedJob(status: ReportStatus.closed);
    app.feedback.put(
      ServiceFeedback(
        id: id,
        workOrderId: 'wo-0042',
        reportId: id,
        submittedBy: fakeRequestor.uid,
        responseTimeRating: 2,
        serviceQualityRating: 3,
        overallSatisfactionRating: 5,
        comments: 'Slow to start, great result.',
        submittedAt: finishedAt,
      ),
    );
    await open(tester, app);

    expect(find.text('You rated this service'), findsOneWidget);
    expect(find.text('Fair'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Excellent'), findsOneWidget);
    expect(find.text('"Slow to start, great result."'), findsOneWidget);
    expect(submit(), findsNothing);
  });

  testWidgets('unfinished work cannot be rated', (tester) async {
    await open(tester, completedJob(status: ReportStatus.inProgress));

    expect(
      find.text(
        'Only completed work can be rated. This report is work started.',
      ),
      findsOneWidget,
    );
    expect(submit(), findsNothing);
  });

  testWidgets('the rating shows on the report once given', (tester) async {
    final app = completedJob();
    await app.pump(tester, start: RoutePaths.staffReportDetailFor(id));
    expect(find.text('Rate this Service'), findsOneWidget);

    await tapInView(tester, find.text('Rate this Service'));
    await tester.pumpAndSettle();
    await rateAll(tester);
    await tapInView(tester, submit());
    await tester.pumpAndSettle();

    expect(find.text('Your rating'), findsOneWidget);
    expect(find.text('Rate this Service'), findsNothing);
    expect(find.text('Closed'), findsWidgets);
  });
}
