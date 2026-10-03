import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/connectivity_service.dart';

import '../support/fake_requestor_app.dart';

/// The faculty and staff app's home, My Reports and bottom bar (Figma
/// `170:2050`, `169:1251`, Objective 3.A), inside the real app and router.
void main() {
  final now = DateTime.now();

  List<dynamic> history() => [
    fakeMyReport(
      'r-newest',
      location: 'AB Bldg, Room 101',
      submittedAt: now.subtract(const Duration(hours: 3)),
    ),
    fakeMyReport(
      'r-second',
      status: ReportStatus.inProgress,
      location: 'Science Bldg, Lab 1',
      requestorCategory: DamageCategory.plumbing,
      submittedAt: now.subtract(const Duration(days: 1)),
    ),
    fakeMyReport(
      'r-third',
      status: ReportStatus.completed,
      location: 'IT Bldg, Networking Laboratory 1',
      requestorCategory: DamageCategory.carpentry,
      submittedAt: now.subtract(const Duration(days: 9)),
    ),
    fakeMyReport(
      'r-oldest',
      status: ReportStatus.closed,
      location: 'Main Library, Level 2',
      submittedAt: now.subtract(const Duration(days: 30)),
    ),
  ];

  RequestorHarness withHistory() => RequestorHarness(reports: history().cast());

  group('home', () {
    testWidgets('greets the requestor by name, with their department', (
      tester,
    ) async {
      await withHistory().pump(tester);

      expect(find.text('Hello, Maria Santos'), findsOneWidget);
      expect(find.text('College of Engineering'), findsOneWidget);
      expect(find.text('Submit Damage\nReport'), findsOneWidget);
      expect(find.text('My Reports'), findsOneWidget);
    });

    testWidgets('without a department the role line is generic', (
      tester,
    ) async {
      await RequestorHarness(profile: fakeRequestorProfile(department: null))
          .pump(tester);

      expect(find.text('Faculty & Staff'), findsOneWidget);
    });

    testWidgets("counts the requestor's own reports by stage", (tester) async {
      final app = withHistory();
      await app.pump(tester);

      expect(find.text('Reports Overview'), findsOneWidget);
      expect(
        find.text('1 Active • 1 In-Progress • 2 Completed'),
        findsOneWidget,
      );
      // Only their own were asked for.
      expect(app.reports.reporterQueries.toSet(), {fakeRequestor.uid});
    });

    testWidgets('lists the three most recent, newest first', (tester) async {
      await withHistory().pump(tester);

      final rows = [
        'AB Bldg, Room 101',
        'Science Bldg, Lab 1',
        'IT Bldg, Networking Laboratory 1',
      ];
      for (final row in rows) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.text('Main Library, Level 2'), findsNothing);
      expect(
        tester.getTopLeft(find.text(rows[0])).dy,
        lessThan(tester.getTopLeft(find.text(rows[1])).dy),
      );
      expect(find.text('3H AGO'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Plumbing'), findsOneWidget);
    });

    testWidgets('a requestor with no reports is told how to file one', (
      tester,
    ) async {
      await RequestorHarness().pump(tester);

      expect(find.textContaining('No reports yet'), findsOneWidget);
      expect(
        find.text('0 Active • 0 In-Progress • 0 Completed'),
        findsOneWidget,
      );
    });

    testWidgets('a failed read says so and can be retried', (tester) async {
      final app = withHistory();
      app.reports.failure = const NetworkFailure('Cannot reach the server.');
      await app.pump(tester);

      expect(find.textContaining('Cannot reach the server.'), findsOneWidget);

      app.reports.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('AB Bldg, Room 101'), findsOneWidget);
    });

    testWidgets('View All and the My Reports tile open My Reports', (
      tester,
    ) async {
      await withHistory().pump(tester);

      await tester.tap(find.text('View All'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffMyReports);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Reports'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffMyReports);
    });

    testWidgets('a recent report opens its details', (tester) async {
      await withHistory().pump(tester);

      await tester.tap(find.text('AB Bldg, Room 101'));
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffReportDetailFor('r-newest'));
      expect(find.text('Report Details'), findsOneWidget);
      expect(find.text('Broken ceiling fan'), findsOneWidget);
    });
  });

  group('My Reports', () {
    Future<RequestorHarness> open(WidgetTester tester) async {
      final app = withHistory();
      await app.pump(tester, start: RoutePaths.staffMyReports);
      return app;
    }

    Finder card(String location) => find.text(location);

    testWidgets("lists every one of the requestor's reports", (tester) async {
      await open(tester);

      expect(find.text('Reports'), findsWidgets);
      expect(find.text('Search your reports...'), findsOneWidget);
      final list = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      for (final location in [
        'AB Bldg, Room 101',
        'Science Bldg, Lab 1',
        'IT Bldg, Networking Laboratory 1',
        'Main Library, Level 2',
      ]) {
        await tester.scrollUntilVisible(
          card(location),
          200,
          scrollable: list.first,
        );
        expect(card(location), findsOneWidget, reason: location);
      }
    });

    testWidgets('a stage filter narrows the list', (tester) async {
      await open(tester);

      // The filters scroll sideways; Completed starts past the edge.
      await tester.ensureVisible(find.text('Completed').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed').first);
      await tester.pumpAndSettle();

      expect(card('AB Bldg, Room 101'), findsNothing);
      expect(card('IT Bldg, Networking Laboratory 1'), findsOneWidget);
      expect(card('Main Library, Level 2'), findsOneWidget);

      await tester.ensureVisible(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(card('AB Bldg, Room 101'), findsOneWidget);
    });

    testWidgets('the search narrows the list, and says when nothing matches', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'library');
      await tester.pumpAndSettle();
      expect(card('Main Library, Level 2'), findsOneWidget);
      expect(card('AB Bldg, Room 101'), findsNothing);

      await tester.enterText(find.byType(TextField), 'no such place');
      await tester.pumpAndSettle();
      expect(find.textContaining('No reports match'), findsOneWidget);
    });

    testWidgets('a card opens what was submitted, and back returns', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(card('Science Bldg, Lab 1'));
      await tester.pumpAndSettle();

      expect(find.text('Report Details'), findsOneWidget);
      expect(find.text('Broken ceiling fan'), findsOneWidget);
      expect(
        find.text('The fan wobbles and sparks at the switch.'),
        findsOneWidget,
      );
      expect(find.text('High'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffMyReports);
    });
  });

  testWidgets("the device's Back from a report returns to My Reports", (
    tester,
  ) async {
    final app = withHistory();
    await app.pump(tester, start: RoutePaths.staffMyReports);
    await tester.tap(find.text('Science Bldg, Lab 1'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Not Home: the report sits on top of My Reports.
    expect(currentPath(tester), RoutePaths.staffMyReports);
  });

  group('live updates (3.B)', () {
    // r-newest as an administrator's move leaves it.
    void move(RequestorHarness app, ReportStatus status) => app.reports.put(
      fakeMyReport(
        'r-newest',
        status: status,
        location: 'AB Bldg, Room 101',
        submittedAt: now.subtract(const Duration(hours: 3)),
      ),
    );

    testWidgets("an administrator's move reaches the home screen by itself", (
      tester,
    ) async {
      final app = withHistory();
      await app.pump(tester);
      expect(
        find.text('1 Active • 1 In-Progress • 2 Completed'),
        findsOneWidget,
      );

      move(app, ReportStatus.inProgress);
      await tester.pumpAndSettle();

      expect(
        find.text('0 Active • 2 In-Progress • 2 Completed'),
        findsOneWidget,
      );
      expect(find.text('Pending'), findsNothing);
      expect(find.text('In Progress'), findsNWidgets(2));
    });

    testWidgets('My Reports keeps its filter while a report moves out of it', (
      tester,
    ) async {
      final app = withHistory();
      await app.pump(tester, start: RoutePaths.staffMyReports);
      await tester.tap(find.text('Pending').first);
      await tester.pumpAndSettle();
      expect(find.text('AB Bldg, Room 101'), findsOneWidget);

      move(app, ReportStatus.completed);
      await tester.pumpAndSettle();

      expect(find.text('AB Bldg, Room 101'), findsNothing);
      expect(find.text('Science Bldg, Lab 1'), findsNothing);
      expect(find.textContaining('No reports match'), findsOneWidget);
    });

    testWidgets('says when the connection is lost, and when it is back', (
      tester,
    ) async {
      final app = withHistory();
      await app.pump(tester);
      expect(find.textContaining("You're offline"), findsNothing);

      app.connectivity.set(BackendReachability.offline);
      await tester.pumpAndSettle();
      expect(find.textContaining("You're offline"), findsOneWidget);
      // What was last loaded stays on screen.
      expect(find.text('AB Bldg, Room 101'), findsOneWidget);

      app.connectivity.set(BackendReachability.online);
      await tester.pumpAndSettle();
      expect(find.textContaining("You're offline"), findsNothing);
    });

    testWidgets('the listener closes when its screens are gone', (
      tester,
    ) async {
      final app = withHistory();
      await app.pump(tester);
      expect(app.reports.openListeners, 1);

      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();
      expect(app.reports.openListeners, 0);

      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(app.reports.openListeners, 1);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(app.reports.openListeners, 0);
    });
  });

  group('bottom bar', () {
    testWidgets('switches between the four tabs', (tester) async {
      await withHistory().pump(tester);

      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffMyReports);

      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffAlerts);
      // The Alerts tab is built now (3.B), not a placeholder.
      expect(find.text('Notifications'), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffProfile);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffHome);
    });

    testWidgets('Back on another tab returns Home rather than leaving', (
      tester,
    ) async {
      await withHistory().pump(tester);
      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffHome);
    });

    testWidgets('signing out returns to the staff sign-in', (tester) async {
      await withHistory().pump(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffLogin);
      expect(find.text('LOGIN TO DASHBOARD'), findsOneWidget);
    });

    testWidgets('the centre button opens the report form over the tabs', (
      tester,
    ) async {
      await withHistory().pump(tester);

      await tester.tap(find.byTooltip('Report damage'));
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffSubmitReport);
      expect(find.text('Report Damage'), findsOneWidget);
      // The form's frame has no bottom bar.
      expect(find.text('Alerts'), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffHome);
    });
  });

  testWidgets('a report filed from the form is on the home screen after', (
    tester,
  ) async {
    final app = RequestorHarness();
    await app.pump(tester);
    expect(find.textContaining('No reports yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Report damage'));
    await tester.pumpAndSettle();

    Future<void> tapVisible(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> choose(String current, String choice) async {
      await tapVisible(find.text(current));
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
    }

    await tester.enterText(
      find.widgetWithText(TextField, 'e.g., Broken Ceiling Fan'),
      'Cracked window pane',
    );
    await choose('Select Level', 'High');
    await choose('Select Type', 'Carpentry');
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Describe the facility damage in detail...',
      ),
      'The pane beside the door is cracked across.',
    );
    await tapVisible(find.text('Tap to take photo or upload from gallery'));
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await choose('Select Building', 'Engineering Building');
    await choose('Select Room', 'Room 203');
    await tapVisible(find.text('Submit Report'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(currentPath(tester), RoutePaths.staffHome);
    expect(find.text('Engineering Building, Room 203'), findsOneWidget);
    expect(find.text('1 Active • 0 In-Progress • 0 Completed'), findsOneWidget);
  });
}
