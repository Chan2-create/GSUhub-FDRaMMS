import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_log_entry.dart';
import 'package:gsuhub/features/damage_reports/data/models/damage_report.dart';
import 'package:gsuhub/features/damage_reports/presentation/report_detail_screen.dart';

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
    DamageCategory? requestorCategory,
    PriorityLevel requestorPriority = PriorityLevel.medium,
    PriorityLevel? officialPriority,
    PriorityLevel? recommendedPriority,
    double? priorityScore,
    String? reviewedBy,
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
    requestorCategory: requestorCategory,
    facilityId: 'fac-science',
    facilityName: 'Science Building',
    locationDescription: 'Laboratory 3',
    requestorPriority: requestorPriority,
    officialPriority: officialPriority,
    recommendedPriority: recommendedPriority,
    priorityScore: priorityScore,
    reviewedBy: reviewedBy,
    reviewedAt: reviewedBy == null ? null : now,
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
    List<AuditLogEntry> history = const [],
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
        activity: Result.success(history),
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

  group("the requestor's choices and the official values", () {
    testWidgets('a report not yet reviewed shows what the requestor chose, '
        'and that it awaits review', (tester) async {
      await open(
        tester,
        'rep-1',
        reports: [
          report(
            'rep-1',
            requestorCategory: DamageCategory.electrical,
            requestorPriority: PriorityLevel.high,
          ),
        ],
      );

      expect(
        find.textContaining('Awaiting administrative review. The values'),
        findsOneWidget,
      );
      expect(find.text('INITIAL CLASSIFICATION'), findsOneWidget);
      expect(find.text('Electrical'), findsWidgets);
      expect(find.text('Requestor-selected'), findsOneWidget);
      // Nothing is official yet, and the keyword match is not passed off
      // as a decision.
      expect(find.text('Awaiting administrative review'), findsNWidgets(2));
      expect(
        find.text(
          'The keywords suggest Plumbing: a suggestion until an '
          'administrator confirms it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Administrator-confirmed'), findsNothing);
      expect(
        find.text('Computed when the four criteria are rated in the review'),
        findsOneWidget,
      );
    });

    testWidgets('a reviewed report keeps the requestor\'s values beside the '
        'official ones', (tester) async {
      await open(
        tester,
        'rep-1',
        reports: [
          report(
            'rep-1',
            requestorCategory: DamageCategory.electrical,
            requestorPriority: PriorityLevel.high,
            classifiedAutomatically: false,
            officialPriority: PriorityLevel.critical,
            recommendedPriority: PriorityLevel.critical,
            priorityScore: 3.7,
            reviewedBy: 'admin-1',
          ),
        ],
      );

      // The requestor's own, as filed.
      expect(find.text('Electrical'), findsWidgets);
      expect(find.text('Requestor-selected'), findsOneWidget);
      // The administrator's, and how they differ.
      expect(find.text('OFFICIAL CLASSIFICATION'), findsOneWidget);
      expect(
        find.text(
          "Changed from the requestor's Electrical, which is kept above.",
        ),
        findsOneWidget,
      );
      expect(find.text('Administrator-confirmed'), findsOneWidget);
      expect(
        find.text("Raised from the requestor's High, which is kept above."),
        findsOneWidget,
      );
      // And the formula's, named as such.
      expect(find.text('System-recommended · score 3.70'), findsOneWidget);
      expect(
        find.textContaining('Awaiting administrative review'),
        findsNothing,
      );
    });

    testWidgets('a review is saved with its reason, against the version of '
        'the report on the page', (tester) async {
      final filed = report(
        'rep-1',
        requestorCategory: DamageCategory.electrical,
      );
      final repository = await open(tester, 'rep-1', reports: [filed]);

      await tapVisible(tester, ratingButton('severity', 4));
      await tapVisible(tester, ratingButton('safetyRisk', 4));
      await tapVisible(tester, ratingButton('locationImportance', 3));
      final reason = find.byKey(const ValueKey('assessment-reason'));
      await tester.ensureVisible(reason);
      await tester.enterText(reason, '  Water is reaching the outlets.  ');
      await tester.pumpAndSettle();
      await tapVisible(tester, confirmButton());

      final saved = repository.assessments.single.assessment;
      expect(saved.reason, 'Water is reaching the outlets.');
      expect(repository.assessmentVersions.single, filed.updatedAt);
      // What the requestor chose is untouched by the review.
      expect(
        repository.byId('rep-1')!.requestorCategory,
        DamageCategory.electrical,
      );
      expect(repository.byId('rep-1')!.requestorPriority, PriorityLevel.medium);
      expect(find.text('Classification and priority saved.'), findsOneWidget);
    });

    testWidgets("a review made over someone else's change is refused, and "
        'the page says who changed it', (tester) async {
      final repository = await open(
        tester,
        'rep-1',
        reports: [report('rep-1')],
      );
      repository.decisionFailure = const ValidationFailure(
        'Ana Reyes changed this report after you opened it here. The latest '
        'details are shown now: check them, then save again.',
      );

      await tapVisible(tester, ratingButton('severity', 2));
      await tapVisible(tester, ratingButton('safetyRisk', 2));
      await tapVisible(tester, ratingButton('locationImportance', 3));
      await tapVisible(tester, confirmButton());

      expect(
        find.textContaining('Ana Reyes changed this report after you opened'),
        findsOneWidget,
      );
      expect(repository.assessments, isEmpty);
      // Nothing was lost: the review can be made again.
      final confirm = tester.widget<FilledButton>(confirmButton());
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('the history spells out what each review changed', (
      tester,
    ) async {
      await open(
        tester,
        'rep-1',
        reports: [report('rep-1', officialPriority: PriorityLevel.critical)],
        history: [
          AuditLogEntry(
            id: 'audit-1',
            actorId: 'admin-1',
            actorName: 'Ramon Dela Cruz',
            action: AuditAction.updated,
            entityType: 'damage_reports',
            entityId: 'rep-1',
            description:
                'Classified as Plumbing; official priority CRITICAL as '
                'recommended (score 3.70). Reason: A burst pipe.',
            changes: const {
              'requestor': {'category': 'electrical', 'priority': 'high'},
              'category': {'from': 'electrical', 'to': 'plumbing'},
              'officialPriority': {'from': null, 'to': 'critical'},
              'firstReview': true,
              'reason': 'A burst pipe.',
            },
            timestamp: now,
          ),
        ],
      );

      expect(find.textContaining('Reason: A burst pipe.'), findsOneWidget);
      expect(
        find.text('Classification: Electrical → Plumbing'),
        findsOneWidget,
      );
      expect(find.text('Official priority: Critical'), findsOneWidget);
      expect(
        find.text('The requestor chose: Electrical, High priority'),
        findsOneWidget,
      );
      expect(find.text('Ramon Dela Cruz'), findsOneWidget);
    });
  });

  group('review moves', () {
    testWidgets('approving says so once it is saved, and the page shows the '
        'new status', (tester) async {
      // Approved once the type and official priority are confirmed
      // (2026-11-26).
      final repository = await open(
        tester,
        'rep-1',
        reports: [
          report(
            'rep-1',
            officialPriority: PriorityLevel.high,
            reviewedBy: 'admin-1',
          ),
        ],
      );

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Approve'));

      expect(repository.transitions.single.to, ReportStatus.approved);
      expect(
        find.text('Report approved. Assign personnel or reschedule it below.'),
        findsOneWidget,
      );
      expect(repository.byId('rep-1')!.status, ReportStatus.approved);
      // No longer on offer: the page follows the report.
      expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
    });

    testWidgets('a move that fails says why, changes nothing, and can be '
        'tried again', (tester) async {
      final repository = await open(
        tester,
        'rep-1',
        reports: [report('rep-1', status: ReportStatus.submitted)],
      );
      repository.decisionFailure = const NetworkFailure(
        'Cannot reach the server. Check your internet connection and '
        'try again.',
      );

      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Start review'),
      );

      expect(find.textContaining('Cannot reach the server.'), findsOneWidget);
      expect(find.textContaining('Review started'), findsNothing);
      expect(repository.byId('rep-1')!.status, ReportStatus.submitted);
      expect(find.widgetWithText(FilledButton, 'Start review'), findsOneWidget);

      // The connection is back.
      repository.decisionFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(repository.transitions, hasLength(2));
      expect(repository.byId('rep-1')!.status, ReportStatus.underReview);
      expect(
        find.text(
          'Review started: the report is Under Review. Confirm its type and '
          'priority below.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a move cannot be sent twice while the first is being saved', (
      tester,
    ) async {
      final repository = await open(
        tester,
        'rep-1',
        reports: [
          report(
            'rep-1',
            officialPriority: PriorityLevel.high,
            reviewedBy: 'admin-1',
          ),
        ],
      );
      final approve = find.widgetWithText(FilledButton, 'Approve');
      await tester.ensureVisible(approve);
      await tester.pumpAndSettle();
      repository.saving = Completer<void>();

      await tester.tap(approve);
      await tester.pump();

      // On its way: the button says so, and neither move can be pressed.
      final pressed = find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(FilledButton),
      );
      expect(pressed, findsOneWidget);
      expect(tester.widget<FilledButton>(pressed).onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Reject'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Report approved.'), findsNothing);
      await tester.tap(pressed, warnIfMissed: false);
      await tester.pump();
      expect(repository.transitions, hasLength(1));

      // Answered: only now is it reported as saved.
      repository.saving!.complete();
      await tester.pumpAndSettle();

      expect(repository.transitions, hasLength(1));
      expect(find.textContaining('Report approved.'), findsOneWidget);
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
