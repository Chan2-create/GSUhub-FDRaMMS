import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/core/widgets/stat_card.dart';
import 'package:gsuhub/features/dashboard/presentation/dashboard_screen.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';

import '../support/fake_admin_backend.dart';

/// The dashboard with data in it (Objective 2.A).
///
/// `dashboard_screen_test.dart` covers the empty and failed states, which
/// meant every chart rendered its placeholder and the populated widgets —
/// donut, legend, table rows, bars — were never built by any test. A
/// LayoutBuilder added to the legend then threw under the screen's own
/// IntrinsicHeight on every frame, and nothing caught it: release builds
/// compile assertions out, so even a screenshot looked correct.
void main() {
  DamageReport report({
    required String id,
    required String title,
    required DamageCategory category,
    required ReportStatus status,
    required String facility,
  }) => DamageReport(
    id: id,
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: title,
    description: 'Seeded for test.',
    category: category,
    facilityId: facility.toLowerCase(),
    facilityName: facility,
    requestorPriority: PriorityLevel.medium,
    status: status,
    submittedAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  final reports = [
    report(
      id: 'rep-0001',
      title: 'Broken Ceiling Fan',
      // The longest label in the palette; it is what exposed the legend
      // truncation, so it belongs in the fixture.
      category: DamageCategory.airConditioning,
      status: ReportStatus.underReview,
      facility: 'Engineering Building',
    ),
    report(
      id: 'rep-0002',
      title: 'Leaking Pipe Under Sink',
      category: DamageCategory.plumbing,
      status: ReportStatus.assigned,
      facility: 'Science Building',
    ),
    report(
      id: 'rep-0003',
      title: 'Flickering Lights',
      category: DamageCategory.electrical,
      status: ReportStatus.inProgress,
      facility: 'Main Library',
    ),
    report(
      id: 'rep-0004',
      title: 'Cracked Wall',
      category: DamageCategory.structural,
      status: ReportStatus.completed,
      facility: 'Engineering Building',
    ),
  ];

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required double width,
  }) async {
    tester.view
      ..physicalSize = Size(width, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      fakeAdminScope(
        reports: Result.success(reports),
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the populated dashboard without exceptions', (
    tester,
  ) async {
    // Above 1100px the screen switches to the two-column layout and wraps
    // it in an IntrinsicHeight, which is the arrangement that broke.
    await pumpDashboard(tester, width: 1440);

    expect(tester.takeException(), isNull);
  });

  testWidgets('counts reports by what the admin does about them', (
    tester,
  ) async {
    await pumpDashboard(tester, width: 1440);

    final byLabel = {
      for (final card in tester.widgetList<StatCard>(find.byType(StatCard)))
        card.label: card.value,
    };

    expect(byLabel['Total Reports'], 4);
    expect(byLabel['Needs Review'], 1); // underReview
    expect(byLabel['In Progress'], 2); // assigned + inProgress
    expect(byLabel['Completed'], 1);
  });

  testWidgets('shows each report in the table', (tester) async {
    await pumpDashboard(tester, width: 1440);

    for (final r in reports) {
      expect(find.text(r.title), findsOneWidget, reason: '${r.id} missing');
    }
  });

  testWidgets('legend labels every category with its share', (tester) async {
    await pumpDashboard(tester, width: 1440);

    // Each category holds one of four reports.
    //
    // This asserts the label *text*, not that it fits: `TextOverflow
    // .ellipsis` clips at paint time and leaves the widget's data intact,
    // so a visually truncated "Air Conditioni..." still matches here.
    // Whether the longest label fits the two-column card is a layout
    // question this cannot answer.
    expect(find.text('Air Conditioning (25%)'), findsOneWidget);
    expect(find.text('Plumbing (25%)'), findsOneWidget);
    expect(find.text('Electrical (25%)'), findsOneWidget);
    expect(find.text('Structural (25%)'), findsOneWidget);
  });

  testWidgets('stacks below 1100px without exceptions', (tester) async {
    await pumpDashboard(tester, width: 900);

    expect(tester.takeException(), isNull);
    expect(find.byType(StatCard), findsNWidgets(4));
  });
}
