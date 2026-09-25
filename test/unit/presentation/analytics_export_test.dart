import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/date_range_filter.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/features/analytics/presentation/analytics_export.dart';
import 'package:gsuhub/features/analytics/presentation/analytics_summary.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';

/// The Export Data file (Objective 2.C).
void main() {
  group('escape', () {
    test('leaves a plain field alone', () {
      expect(AnalyticsExport.escape('Main Library'), 'Main Library');
    });

    test('quotes commas, quotes and line breaks per RFC 4180', () {
      expect(AnalyticsExport.escape('Room 1, Level 2'), '"Room 1, Level 2"');
      expect(AnalyticsExport.escape('The "big" leak'), '"The ""big"" leak"');
      expect(AnalyticsExport.escape('two\nlines'), '"two\nlines"');
    });

    test('defuses a field that a spreadsheet would run as a formula', () {
      // Titles are typed by requestors; this must open as text.
      expect(
        AnalyticsExport.escape('=HYPERLINK("http://x","click")'),
        '"\'=HYPERLINK(""http://x"",""click"")"',
      );
      expect(AnalyticsExport.escape('+1 555'), "'+1 555");
      expect(AnalyticsExport.escape('-5'), "'-5");
      expect(AnalyticsExport.escape('@SUM(A1)'), "'@SUM(A1)");
    });
  });

  test('names the file after the period and the day', () {
    expect(
      AnalyticsExport.fileName(DateRangeFilter.last30, DateTime(2026, 9, 25)),
      'gsuhub-analytics-last-30-days-2026-09-25.csv',
    );
  });

  test('lists the period\'s reports, newest first, under a summary', () {
    final now = DateTime(2026, 9, 25, 12);
    DamageReport report(String id, DateTime submitted, {String? title}) =>
        DamageReport(
          id: id,
          reporterId: 'faculty-1',
          reporterName: 'Maria Santos',
          title: title ?? 'Damage $id',
          description: 'Seeded for test.',
          requestorPriority: PriorityLevel.high,
          status: ReportStatus.submitted,
          category: DamageCategory.plumbing,
          facilityName: 'Main Library',
          submittedAt: submitted,
          updatedAt: submitted,
        );

    final reports = [
      report('rep-0001', DateTime(2026, 9)),
      report('rep-0002', DateTime(2026, 9, 20), title: 'Leak, near stairs'),
      report('rep-0003', DateTime(2026, 6)), // outside the period
    ];
    final summary = AnalyticsSummary.compute(
      reports: reports,
      workOrders: const [],
      context: DateFilterContext(range: DateRangeFilter.last30, now: now),
    );

    final csv = AnalyticsExport.buildCsv(
      summary: summary,
      reports: reports,
      workOrders: const [],
      personnelNames: const {},
      now: now,
    );
    final lines = csv.split('\r\n');

    expect(lines.first, 'GSUhub Analytics Export');
    expect(lines, contains('Period,Last 30 Days'));
    expect(lines, contains('Total reports,2'));
    final header = lines.indexOf(AnalyticsExport.reportColumns.join(','));
    expect(header, greaterThan(0));
    final rows = lines.sublist(header + 1);
    expect(rows, hasLength(2));
    expect(rows.first, startsWith('#REP-0002,"Leak, near stairs",Plumbing'));
    // An official priority not yet confirmed is marked as such.
    expect(rows.first, contains('HIGH (unconfirmed)'));
    expect(rows.last, startsWith('#REP-0001,'));
  });
}
