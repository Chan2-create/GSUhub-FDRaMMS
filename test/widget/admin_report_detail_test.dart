import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/presentation/report_detail_screen.dart';

import '../support/fake_admin_backend.dart';

/// The console's report page: the classification and priority review,
/// and possible duplicates (Objectives 4.A–4.C).
void main() {
  final now = DateTime.now();

  DamageReport report(
    String id, {
    String title = 'Leaking pipe under the sink',
    String description = 'Water is flooding the floor of the lab.',
    DamageCategory? category = DamageCategory.plumbing,
    bool classifiedAutomatically = true,
    PriorityLevel? officialPriority,
    ReportStatus status = ReportStatus.underReview,
    String? workOrderId,
    Duration filedAgo = Duration.zero,
  }) => DamageReport(
    id: id,
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: title,
    description: description,
    category: category,
    classifiedAutomatically: classifiedAutomatically,
    facilityId: 'fac-science',
    facilityName: 'Science Building',
    locationDescription: 'Laboratory 3',
    requestorPriority: PriorityLevel.medium,
    officialPriority: officialPriority,
    status: status,
    workOrderId: workOrderId,
    submittedAt: now.subtract(filedAgo),
    updatedAt: now,
  );

  Future<FakeDamageReportRepository> open(
    WidgetTester tester,
    String id, {
    required List<DamageReport> reports,
    int similarReports = 1,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = FakeDamageReportRepository(Result.success(reports))
      ..similarCount = Result.success(similarReports);
    final router = GoRouter(
      initialLocation: RoutePaths.adminReportDetailFor(id),
      routes: [
        GoRoute(
          path: RoutePaths.adminReportDetail,
          builder: (context, state) => Scaffold(
            body: ReportDetailScreen(
              reportId: state.pathParameters['reportId']!,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      fakeAdminScope(
        reportRepository: repository,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder ratingButton(String criterion, int rating) => find.descendant(
    of: find.byKey(ValueKey('rating-$criterion')),
    matching: find.text('$rating'),
  );

  Finder officialButton(String level) => find.descendant(
    of: find.byKey(const ValueKey('official-priority')),
    matching: find.text(level),
  );

  Finder confirmButton() =>
      find.widgetWithText(FilledButton, 'Confirm classification and priority');

  group('classification and priority', () {
    testWidgets("pre-fills the classifier's type and the Frequency hint", (
      tester,
    ) async {
      await open(
        tester,
        'rep-1',
        reports: [report('rep-1')],
        similarReports: 3,
      );

      expect(find.text('Classification and priority'), findsOneWidget);
      expect(
        find.text('Keywords found: “leaking pipe”, “flooding” → Plumbing.'),
        findsOneWidget,
      );
      // Three reports of the damage at the facility suggest High.
      expect(
        find.textContaining(
          '3 reports of Plumbing at this facility in the last 30 days '
          '(this one included) — suggests 3, High, filled in for you.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Rate all four criteria to compute the score.'),
        findsOneWidget,
      );
      final confirm = tester.widget<FilledButton>(confirmButton());
      expect(confirm.onPressed, isNull);
    });

    testWidgets('scores as the criteria are rated, and saves the review', (
      tester,
    ) async {
      final repository = await open(
        tester,
        'rep-1',
        reports: [report('rep-1')],
        similarReports: 3,
      );

      await tapVisible(tester, ratingButton('severity', 4));
      await tapVisible(tester, ratingButton('safetyRisk', 4));
      await tapVisible(tester, ratingButton('locationImportance', 3));

      // 0.40×4 + 0.30×4 + 0.20×3 (the hint) + 0.10×3 = 3.70: Critical.
      expect(find.text('3.70'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);

      await tapVisible(tester, confirmButton());

      final saved = repository.assessments.single;
      expect(saved.reportId, 'rep-1');
      expect(saved.assessment.category, DamageCategory.plumbing);
      expect(saved.assessment.classifiedAutomatically, isTrue);
      expect(saved.assessment.frequencyRating, 3);
      expect(saved.assessment.priorityScore, 3.70);
      expect(saved.assessment.recommendedPriority, PriorityLevel.critical);
      expect(saved.assessment.officialPriority, PriorityLevel.critical);
      expect(find.text('Classification and priority saved.'), findsOneWidget);

      // The page follows the saved report: confirmed, nothing to save.
      expect(find.text('Saved.'), findsOneWidget);
      final again = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      expect(again.onPressed, isNull);
    });

    testWidgets('records an official level the administrator changed', (
      tester,
    ) async {
      final repository = await open(
        tester,
        'rep-1',
        reports: [report('rep-1')],
      );

      await tapVisible(tester, ratingButton('severity', 2));
      await tapVisible(tester, ratingButton('safetyRisk', 2));
      await tapVisible(tester, ratingButton('locationImportance', 3));
      // One report — this one — suggests Low Frequency: 1.90, Medium.
      expect(find.text('1.90'), findsOneWidget);

      await tapVisible(tester, officialButton('High'));

      expect(
        find.text(
          'Differs from the recommended Medium: saving records it as your '
          'change.',
        ),
        findsOneWidget,
      );

      await tapVisible(tester, confirmButton());

      final saved = repository.assessments.single.assessment;
      expect(saved.recommendedPriority, PriorityLevel.medium);
      expect(saved.officialPriority, PriorityLevel.high);
    });

    testWidgets('a report no keyword matched waits for its type', (
      tester,
    ) async {
      final repository = await open(
        tester,
        'rep-1',
        reports: [
          report(
            'rep-1',
            title: 'Ceiling stain',
            description: 'A brown stain is spreading over the door.',
            category: null,
            classifiedAutomatically: false,
          ),
        ],
        similarReports: 2,
      );

      expect(
        find.text(
          'No keyword in the title or description matched, so the type is '
          'yours to choose.',
        ),
        findsOneWidget,
      );
      expect(find.text('Choose the damage type.'), findsOneWidget);
      expect(
        find.text('Choose the damage type to count similar reports.'),
        findsOneWidget,
      );

      await tapVisible(tester, find.text('Choose the damage type'));
      await tester.tap(find.text('Structural').last);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('2 reports of Structural at this facility'),
        findsOneWidget,
      );
      expect(
        repository.similarQueries.last.category,
        DamageCategory.structural,
      );
      expect(repository.similarQueries.last.facilityId, 'fac-science');

      await tapVisible(tester, ratingButton('severity', 2));
      await tapVisible(tester, ratingButton('safetyRisk', 1));
      await tapVisible(tester, ratingButton('locationImportance', 2));
      await tapVisible(tester, confirmButton());

      final saved = repository.assessments.single.assessment;
      expect(saved.category, DamageCategory.structural);
      // Chosen by the administrator, not by the keywords.
      expect(saved.classifiedAutomatically, isFalse);
    });

    testWidgets('is gone once the work is assigned', (tester) async {
      await open(
        tester,
        'rep-1',
        reports: [
          report(
            'rep-1',
            status: ReportStatus.assigned,
            workOrderId: 'wo-1',
            officialPriority: PriorityLevel.high,
          ),
        ],
      );

      expect(find.text('Classification and priority'), findsNothing);
      // The summary still says what was decided.
      expect(find.text('Classification'), findsOneWidget);
      expect(find.text('Plumbing'), findsWidgets);
    });

    testWidgets('a save the repository refuses is reported', (tester) async {
      final repository = await open(
        tester,
        'rep-1',
        reports: [report('rep-1')],
      );
      repository.decisionFailure = const ValidationFailure(
        'This report is ASSIGNED.',
      );

      await tapVisible(tester, ratingButton('severity', 2));
      await tapVisible(tester, ratingButton('safetyRisk', 2));
      await tapVisible(tester, ratingButton('locationImportance', 3));
      await tapVisible(tester, confirmButton());

      expect(find.text('This report is ASSIGNED.'), findsOneWidget);
      expect(repository.assessments, isEmpty);
    });
  });

  group('possible duplicates', () {
    List<DamageReport> pair() => [
      report(
        'rep-1',
        title: 'Lights flicker',
        description: 'The lab lights flicker all day.',
        category: DamageCategory.electrical,
        filedAgo: const Duration(hours: 5),
      ),
      report(
        'rep-2',
        title: 'Flickering lights in the lab',
        description: 'They have flickered since morning.',
        category: DamageCategory.electrical,
        status: ReportStatus.submitted,
      ),
    ];

    testWidgets('lists the report it may duplicate, with the reasons', (
      tester,
    ) async {
      await open(tester, 'rep-2', reports: pair());

      expect(find.text('Possible duplicates (1)'), findsOneWidget);
      expect(find.text('Lights flicker'), findsOneWidget);
      expect(
        find.textContaining('same damage type (Electrical)'),
        findsOneWidget,
      );
      expect(find.textContaining('filed 5 hours earlier'), findsOneWidget);
    });

    testWidgets('merges this report into the earlier one, once confirmed', (
      tester,
    ) async {
      final repository = await open(tester, 'rep-2', reports: pair());

      await tapVisible(tester, find.text('Merge this report into #REP-1'));
      expect(find.text('Merge as a duplicate?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();

      expect(repository.merges.single.parentReportId, 'rep-1');
      expect(repository.merges.single.duplicateReportIds, ['rep-2']);
      expect(find.text('Merged as a duplicate'), findsOneWidget);
      expect(
        find.text('GSU is tracking this damage under #REP-1.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the merge changes nothing', (tester) async {
      final repository = await open(tester, 'rep-2', reports: pair());

      await tapVisible(tester, find.text('Merge this report into #REP-1'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.merges, isEmpty);
      expect(find.text('Possible duplicates (1)'), findsOneWidget);
    });

    testWidgets('keeps the two separate', (tester) async {
      final repository = await open(tester, 'rep-1', reports: pair());

      // From the earlier report, the later one is the one to fold in.
      expect(find.text('Merge #REP-2 into this report'), findsOneWidget);

      await tapVisible(tester, find.text('Keep separate'));

      expect(repository.keptSeparate.single, (
        reportId: 'rep-1',
        otherReportId: 'rep-2',
      ));
      expect(find.text('Kept separate from #REP-2.'), findsOneWidget);
      expect(find.text('Possible duplicates'), findsOneWidget);
      expect(find.textContaining('None found.'), findsOneWidget);
    });
  });
}
