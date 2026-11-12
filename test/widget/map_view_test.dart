import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/data/geo_coordinates.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/reporting/presentation/map/report_map.dart';

import '../support/fake_personnel_app.dart';
import '../support/fake_requestor_app.dart' show currentPath;

/// Map View (2026-11-12): the geo-tagged damage reports as pins, each
/// read together with its facility, location description and photos, as
/// the manuscript says a geo-tag is (§2 "Geo-Tagging and Location-Based
/// Reporting"). Over the in-memory backend, with no map tiles fetched.
void main() {
  const library = GeoCoordinates(latitude: 7.2051, longitude: 126.5359);
  const engineering = GeoCoordinates(latitude: 7.2048, longitude: 126.5354);
  const gym = GeoCoordinates(latitude: 7.2040, longitude: 126.5362);

  /// Two open reports with a geo-tag, one open without, one closed with.
  Future<PersonnelHarness> console() async {
    final app = PersonnelHarness(signedIn: fakeAdministrator);
    await app.data.addPersonnel(
      fakeAdministrator.uid,
      role: UserRole.admin,
      fullName: 'Ramon Dela Cruz',
    );
    await app.data.addReport(
      'rep-1',
      title: 'Leaking pipe',
      locationDescription: 'Second floor, beside the stairs',
      coordinates: engineering,
      submittedAt: DateTime.utc(2026, 11, 2),
    );
    await app.data.addReport(
      'rep-2',
      title: 'Broken window',
      status: ReportStatus.inProgress,
      coordinates: library,
      submittedAt: DateTime.utc(2026, 11, 3),
    );
    await app.data.addReport('rep-3', title: 'Loose handrail');
    await app.data.addReport(
      'rep-4',
      title: 'Dead socket',
      status: ReportStatus.closed,
      coordinates: gym,
    );
    return app;
  }

  Future<void> open(
    PersonnelHarness app,
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
  }) => app.pump(tester, start: RoutePaths.adminMapView, size: size);

  Finder pin(String title) =>
      find.byTooltip('$title, Engineering Building', skipOffstage: false);

  testWidgets('pins the open geo-tagged reports and counts the rest', (
    tester,
  ) async {
    final app = await console();
    await open(app, tester);

    expect(find.byType(ReportMap), findsOneWidget);
    expect(find.text('2 open reports with a geo-tag'), findsOneWidget);
    expect(
      find.byTooltip(
        'Leaking pipe, Engineering Building · '
        'Second floor, beside the stairs',
      ),
      findsOneWidget,
    );
    expect(pin('Broken window'), findsOneWidget);
    // Closed, so off the map until asked for; no geo-tag, so never on it.
    expect(pin('Dead socket'), findsNothing);
    expect(pin('Loose handrail'), findsNothing);
    expect(
      find.text(
        '1 open report was filed without a geo-tag and is not on the map.',
      ),
      findsOneWidget,
    );
    // Newest first in the list beside the map.
    expect(
      tester.getTopLeft(find.text('Broken window')).dy,
      lessThan(tester.getTopLeft(find.text('Leaking pipe')).dy),
    );
  });

  testWidgets('finished reports join the map when asked for', (tester) async {
    final app = await console();
    await open(app, tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Finished reports'));
    await tester.pumpAndSettle();

    expect(find.text('3 reports with a geo-tag'), findsOneWidget);
    expect(pin('Dead socket'), findsOneWidget);
    expect(
      find.text('1 report was filed without a geo-tag and is not on the map.'),
      findsOneWidget,
    );
  });

  testWidgets('a pin shows what a geo-tag is read with, and leads to the '
      'report', (tester) async {
    final app = await console();
    await open(app, tester);

    await tester.tap(
      find.byTooltip(
        'Leaking pipe, Engineering Building · '
        'Second floor, beside the stairs',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected report'), findsOneWidget);
    expect(find.text('#REP-1'), findsOneWidget);
    expect(find.text('Engineering Building'), findsOneWidget);
    expect(find.text('Second floor, beside the stairs'), findsOneWidget);
    expect(find.text('7.20480, 126.53540'), findsOneWidget);
    expect(
      find.text('No photos were attached to this report.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Open report'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), RoutePaths.adminReportDetailFor('rep-1'));
  });

  testWidgets('the list selects a pin too, and gives the list back', (
    tester,
  ) async {
    final app = await console();
    await open(app, tester);

    await tester.tap(find.text('Broken window'));
    await tester.pumpAndSettle();
    expect(find.text('Selected report'), findsOneWidget);
    expect(find.text('7.20510, 126.53590'), findsOneWidget);

    await tester.tap(find.text('All reports'));
    await tester.pumpAndSettle();
    expect(find.text('Reports on the map'), findsOneWidget);
    expect(find.text('Selected report'), findsNothing);
  });

  testWidgets('says so when no report has a geo-tag', (tester) async {
    final app = PersonnelHarness(signedIn: fakeAdministrator);
    await app.data.addPersonnel(fakeAdministrator.uid, role: UserRole.admin);
    await app.data.addReport('rep-3', title: 'Loose handrail');
    await open(app, tester);

    expect(find.text('No open report has a geo-tag to show.'), findsOneWidget);
    expect(find.byType(ReportMap), findsNothing);
    expect(find.text('Reports on the map'), findsNothing);
  });

  testWidgets('fits a phone: the reports go under the map', (tester) async {
    final app = await console();
    await open(app, tester, size: const Size(360, 900));

    expect(
      tester.getTopLeft(find.text('Reports on the map')).dy,
      greaterThan(tester.getBottomLeft(find.byType(ReportMap)).dy),
    );
    // Each row starts at the card's left edge, under its heading: not
    // centred in the card.
    expect(
      tester.getTopLeft(find.text('Broken window')).dx,
      tester.getTopLeft(find.text('Reports on the map')).dx,
    );
  });

  testWidgets('Damage Reports previews the map and links to it', (
    tester,
  ) async {
    final app = await console();
    await app.pump(
      tester,
      start: RoutePaths.adminReports,
      size: const Size(1440, 1800),
    );

    expect(find.text('Campus View'), findsOneWidget);
    expect(find.byType(ReportMap), findsOneWidget);
    await tester.ensureVisible(find.text('Open Map View'));
    await tester.tap(find.text('Open Map View'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), RoutePaths.adminMapView);
  });
}
