import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/connectivity_service.dart';
import 'package:gsuhub/shells/mobile/mobile_header.dart';

import '../support/fake_requestor_app.dart';

/// The faculty and staff app's home, My Reports and bottom bar (Figma
/// `170:2050`, `169:1251`, Objective 3.A), inside the real app and router.
void main() {
  /// The Notifications tab (back in the bar since 2026-11-26).
  Finder notificationsTab() => find.text('Notifications');

  final now = DateTime.now();

  List<dynamic> history() => [
    fakeMyReport(
      'r-newest',
      location: 'AB Bldg, Room 101',
      submittedAt: now.subtract(const Duration(minutes: 20)),
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

  testWidgets('the header reaches screen readers, not only the page', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await RequestorHarness().pump(tester);

    // The page's route barrier hid everything above it in the shell's
    // column until the page area got a semantics container of its own.
    expect(find.bySemanticsLabel('GSUhub'), findsOneWidget);
    semantics.dispose();
  });

  group('home', () {
    testWidgets('greets the requestor by name, with their department', (
      tester,
    ) async {
      await withHistory().pump(tester);

      expect(find.text('Hello, Maria Santos'), findsOneWidget);
      expect(find.text('College of Engineering'), findsOneWidget);
    });

    testWidgets('has no Submit Damage Report or My Reports tiles and no '
        'View All, and no gap where they were (2026-11-26)', (tester) async {
      await withHistory().pump(tester);

      expect(find.textContaining('Submit Damage'), findsNothing);
      expect(find.text('My Reports'), findsNothing);
      expect(find.text('View All'), findsNothing);
      // The overview follows the greeting card, 16 apart as everything
      // else on the page, and the recent reports follow it.
      final greeting = find.ancestor(
        of: find.text('Hello, Maria Santos'),
        matching: find.byType(Container),
      );
      final overview = find.ancestor(
        of: find.text('Reports Overview'),
        matching: find.byType(Container),
      );
      expect(
        tester.getTopLeft(overview.first).dy -
            tester.getBottomLeft(greeting.first).dy,
        16,
      );
      expect(
        tester.getTopLeft(find.text('Recent Reports')).dy,
        tester.getBottomLeft(overview.first).dy + 16,
      );
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
      expect(find.text('20M AGO'), findsOneWidget);
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
        submittedAt: now.subtract(const Duration(minutes: 20)),
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

      // The notifications: no report on screen.
      await tester.tap(notificationsTab());
      await tester.pumpAndSettle();
      expect(app.reports.openListeners, 0);

      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(app.reports.openListeners, 1);

      await logOutFromProfile(tester);
      expect(app.reports.openListeners, 0);
    });
  });

  group('help (2026-11-26)', () {
    testWidgets("the header's question mark opens Help, over the page it "
        'was opened from', (tester) async {
      await withHistory().pump(tester);
      expect(find.byKey(MobileHeader.helpKey), findsOneWidget);

      await tester.tap(find.byKey(MobileHeader.helpKey));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffHelp);
      expect(find.text('Help'), findsOneWidget);

      // Back returns to the page beneath.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffHome);
    });

    testWidgets('covers sending a report, the statuses, the QR code and '
        'GSU', (tester) async {
      await RequestorHarness().pump(tester, start: RoutePaths.staffHelp);

      final page = find.byType(Scrollable).first;
      Future<void> sees(Finder finder) async {
        await tester.scrollUntilVisible(finder, 200, scrollable: page);
        expect(finder, findsOneWidget);
      }

      await sees(find.text('Sending a damage report'));
      await sees(find.textContaining('Tap the gold +'));
      await sees(find.text('What each status means'));
      for (final status in const [
        'Pending',
        'Under Review',
        'Approved',
        'Scheduled',
        'Assigned',
        'In Progress',
        'Completed',
        'Rejected',
      ]) {
        await sees(
          find.textContaining(RegExp('^$status\\. '), findRichText: true),
        );
      }
      await sees(find.text('Scanning a QR code'));
      await sees(find.textContaining('QR button at the top right'));
      await sees(find.text('Contacting GSU'));
      await sees(find.textContaining("GSU Administrator's Office"));
    });

    testWidgets('opened directly, Back goes Home', (tester) async {
      await RequestorHarness().pump(tester, start: RoutePaths.staffHelp);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffHome);
    });
  });

  group('bottom bar', () {
    testWidgets('switches between the four tabs, two each side of the + '
        '(2026-11-26)', (tester) async {
      await withHistory().pump(tester);

      // Home, Reports, [+], Notifications, Profile.
      final plus = tester.getCenter(find.byTooltip('Report damage')).dx;
      final xs = [
        for (final label in ['Home', 'Reports', 'Notifications', 'Profile'])
          tester.getCenter(find.text(label)).dx,
      ];
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(plus));
      expect(xs[2], greaterThan(plus));
      expect(xs[3], greaterThan(xs[2]));

      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffMyReports);

      await tester.tap(notificationsTab());
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffAlerts);
      // The tab, and the page's title.
      expect(notificationsTab(), findsNWidgets(2));

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffProfile);
      // The profile: who they are, and what their account is.
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('Faculty'), findsWidgets);
      expect(find.text('Active account'), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffHome);
    });

    testWidgets('Back on another tab returns Home rather than leaving', (
      tester,
    ) async {
      await withHistory().pump(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffHome);
    });

    testWidgets('Back from the notifications returns Home too', (tester) async {
      await withHistory().pump(tester);
      await tester.tap(notificationsTab());
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffAlerts);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffHome);
    });

    testWidgets('Logout asks first, and Cancel keeps the session', (
      tester,
    ) async {
      await withHistory().pump(tester);

      await logOutFromProfile(tester, confirm: false);

      expect(find.text('Log out of GSUhub?'), findsNothing);
      expect(currentPath(tester), RoutePaths.staffProfile);
    });

    testWidgets('signing out returns to the staff sign-in', (tester) async {
      await withHistory().pump(tester);

      await logOutFromProfile(tester);

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
