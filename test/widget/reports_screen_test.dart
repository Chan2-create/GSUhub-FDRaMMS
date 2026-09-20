import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/presentation/reports_screen.dart';

import '../support/fake_admin_backend.dart';

/// Damage Reports table, filters and pagination (Objective 2.B).
void main() {
  DamageReport report({
    required String id,
    required String title,
    DamageCategory? category = DamageCategory.electrical,
    PriorityLevel requestorPriority = PriorityLevel.medium,
    PriorityLevel? officialPriority,
    ReportStatus status = ReportStatus.submitted,
    String reporter = 'Maria Santos',
  }) => DamageReport(
    id: id,
    reporterId: 'faculty-1',
    reporterName: reporter,
    title: title,
    description: 'Seeded for test.',
    category: category,
    facilityName: 'Engineering Building',
    requestorPriority: requestorPriority,
    officialPriority: officialPriority,
    status: status,
    submittedAt: DateTime.utc(2026, 9, 18),
    updatedAt: DateTime.utc(2026, 9, 18),
  );

  Future<void> pump(WidgetTester tester, List<DamageReport> reports) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      fakeAdminScope(
        reports: Result.success(reports),
        child: const MaterialApp(home: Scaffold(body: ReportsScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens a filter dropdown and picks [option].
  Future<void> choose(
    WidgetTester tester,
    String dropdown,
    String option,
  ) async {
    await tester.tap(find.text(dropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  group('table', () {
    testWidgets('lists reports with their reporter and status', (tester) async {
      await pump(tester, [
        report(id: 'rep-1', title: 'Broken Ceiling Fan'),
        report(id: 'rep-2', title: 'Leaking Pipe', reporter: 'John Cruz'),
      ]);

      // The design's table carries no title column, so a row is
      // identified by its number, reporter, type and location.
      expect(find.text('#REP-1'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('John Cruz'), findsOneWidget);
      expect(find.text('Electrical'), findsNWidgets(2));
      // The 2.A label for `submitted`, kept for 2.B.
      expect(find.text('PENDING'), findsWidgets);
    });

    testWidgets('an unclassified report says so rather than blank', (
      tester,
    ) async {
      await pump(tester, [
        report(id: 'rep-1', title: 'Ceiling stain', category: null),
      ]);

      expect(find.text('Unclassified'), findsOneWidget);
    });

    testWidgets('marks an unconfirmed priority apart from a confirmed one', (
      tester,
    ) async {
      await pump(tester, [
        report(
          id: 'rep-1',
          title: 'Unconfirmed',
          requestorPriority: PriorityLevel.high,
        ),
        report(
          id: 'rep-2',
          title: 'Confirmed',
          requestorPriority: PriorityLevel.low,
          officialPriority: PriorityLevel.high,
        ),
      ]);

      // The requestor's own priority is marked with an asterisk and a
      // tooltip; the administrator's confirmed one is not.
      expect(find.text('HIGH*'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
    });

    testWidgets('shows an empty state on a database with no reports', (
      tester,
    ) async {
      await pump(tester, []);

      expect(
        find.text('No damage reports have been submitted yet.'),
        findsOneWidget,
      );
    });
  });

  group('filters', () {
    testWidgets('damage type narrows the table', (tester) async {
      await pump(tester, [
        report(id: 'rep-1', title: 'Broken Ceiling Fan'),
        report(
          id: 'rep-2',
          title: 'Leaking Pipe',
          category: DamageCategory.plumbing,
        ),
      ]);

      await choose(tester, 'Damage Type', 'Plumbing');

      expect(find.text('#REP-2'), findsOneWidget);
      expect(find.text('#REP-1'), findsNothing);
    });

    testWidgets('status narrows the table', (tester) async {
      await pump(tester, [
        report(id: 'rep-1', title: 'Broken Ceiling Fan'),
        report(
          id: 'rep-2',
          title: 'Leaking Pipe',
          status: ReportStatus.approved,
        ),
      ]);

      await choose(tester, 'Status', 'APPROVED');

      expect(find.text('#REP-2'), findsOneWidget);
      expect(find.text('#REP-1'), findsNothing);
    });

    testWidgets('priority filters on the effective priority', (tester) async {
      // rep-2's official priority overrides the requestor's, so filtering
      // on CRITICAL must find it and not the one that merely asked for it.
      await pump(tester, [
        report(
          id: 'rep-1',
          title: 'Asked for critical',
          requestorPriority: PriorityLevel.critical,
          officialPriority: PriorityLevel.low,
        ),
        report(
          id: 'rep-2',
          title: 'Confirmed critical',
          requestorPriority: PriorityLevel.low,
          officialPriority: PriorityLevel.critical,
        ),
      ]);

      await choose(tester, 'Priority', 'CRITICAL');

      expect(find.text('#REP-2'), findsOneWidget);
      expect(find.text('#REP-1'), findsNothing);
    });

    testWidgets('a filter matching nothing says so, distinctly', (
      tester,
    ) async {
      await pump(tester, [report(id: 'rep-1', title: 'Broken Ceiling Fan')]);

      await choose(tester, 'Damage Type', 'Plumbing');

      // Different wording from "none have been submitted": the database is
      // not empty, the filter is just narrow.
      expect(find.text('No reports match these filters.'), findsOneWidget);
    });

    testWidgets('Clear all filters restores every row', (tester) async {
      await pump(tester, [
        report(id: 'rep-1', title: 'Broken Ceiling Fan'),
        report(
          id: 'rep-2',
          title: 'Leaking Pipe',
          category: DamageCategory.plumbing,
        ),
      ]);

      await choose(tester, 'Damage Type', 'Plumbing');
      expect(find.text('#REP-1'), findsNothing);

      await tester.tap(find.text('Clear all filters'));
      await tester.pumpAndSettle();

      expect(find.text('#REP-1'), findsOneWidget);
      expect(find.text('#REP-2'), findsOneWidget);
    });
  });

  group('pagination', () {
    List<DamageReport> many(int count) => [
      for (var i = 1; i <= count; i++)
        report(id: 'rep-$i', title: 'Report number $i'),
    ];

    testWidgets('splits the list into pages of ten', (tester) async {
      await pump(tester, many(12));

      expect(find.text('Showing 1 to 10 of 12 results'), findsOneWidget);
      expect(find.text('#REP-1'), findsOneWidget);
      expect(find.text('#REP-11'), findsNothing);
    });

    testWidgets('the second page shows the remainder', (tester) async {
      await pump(tester, many(12));

      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();

      expect(find.text('Showing 11 to 12 of 12 results'), findsOneWidget);
      expect(find.text('#REP-11'), findsOneWidget);
      expect(find.text('#REP-1'), findsNothing);
    });

    testWidgets('filtering returns to the first page', (tester) async {
      // Otherwise a filter leaving three results while sitting on page two
      // shows an empty table that looks like a bug.
      await pump(tester, [
        ...many(12),
        report(
          id: 'rep-plumb',
          title: 'Leaking Pipe',
          category: DamageCategory.plumbing,
        ),
      ]);

      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      expect(find.text('Showing 11 to 13 of 13 results'), findsOneWidget);

      await choose(tester, 'Damage Type', 'Plumbing');

      expect(find.text('Showing 1 to 1 of 1 results'), findsOneWidget);
      expect(find.text('#REP-PLUMB'), findsOneWidget);
    });
  });
}
