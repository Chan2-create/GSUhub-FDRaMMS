import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/notification_service.dart';

import '../support/fake_notifications.dart';
import '../support/fake_requestor_app.dart';

/// The Alerts tab (Figma `169:1459`, Objective 3.B), inside the real app.
void main() {
  final now = DateTime.now();

  RequestorHarness withNotices() => RequestorHarness(
    reports: [fakeMyReport('r-newest')],
    notices: [
      fakeNotice(
        'n-approved',
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
      fakeNotice(
        'n-assigned',
        type: NotificationType.workOrderAssigned,
        body: 'Juan Luna was assigned to your report "Broken ceiling fan".',
        createdAt: now.subtract(const Duration(minutes: 45)),
      ),
      fakeNotice(
        'n-received',
        type: NotificationType.reportAcknowledged,
        body: 'The General Services Unit received your report.',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
    ],
  );

  /// The badge on the Alerts tab, or null when there is none.
  String? badgeText(WidgetTester tester) {
    final badges = find.byType(Badge);
    if (badges.evaluate().isEmpty) return null;
    final label = tester.widget<Badge>(badges.first).label! as Text;
    return label.data;
  }

  testWidgets('groups them Today and Earlier, newest first', (tester) async {
    await withNotices().pump(tester, start: RoutePaths.staffAlerts);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('2 minutes ago'), findsOneWidget);
    expect(find.text('45 minutes ago'), findsOneWidget);

    final order = [
      find.text('Today'),
      find.textContaining('was approved'),
      find.textContaining('Juan Luna'),
      find.text('Earlier'),
      find.textContaining('received your report'),
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        tester.getTopLeft(order[i - 1]).dy,
        lessThan(tester.getTopLeft(order[i]).dy),
      );
    }
  });

  testWidgets('unread are bold, read are not', (tester) async {
    await withNotices().pump(tester, start: RoutePaths.staffAlerts);

    FontWeight? weightOf(Finder text) =>
        tester.widget<Text>(text).style?.fontWeight;
    expect(weightOf(find.textContaining('was approved')), FontWeight.w700);
    expect(
      weightOf(find.textContaining('received your report')),
      FontWeight.w400,
    );
  });

  testWidgets('the Alerts badge counts unread, live, and clears on read', (
    tester,
  ) async {
    final app = withNotices();
    await app.pump(tester);
    expect(badgeText(tester), '2');

    app.notifications.deliver(
      fakeNotice('n-started', body: 'Work has started on your report.'),
    );
    await tester.pumpAndSettle();
    expect(badgeText(tester), '3');

    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();

    expect(badgeText(tester), isNull);
    expect(find.text('Mark all as read'), findsNothing);
    expect(app.notifications.markAllCalls, 1);
  });

  testWidgets('tapping one marks it read and opens its report', (tester) async {
    final app = withNotices();
    await app.pump(tester, start: RoutePaths.staffAlerts);

    await tester.tap(find.textContaining('was approved'));
    await tester.pumpAndSettle();

    expect(app.notifications.markedRead, ['n-approved']);
    expect(currentPath(tester), RoutePaths.staffReportDetailFor('r-newest'));
    expect(badgeText(tester), '1');

    // Back returns to the list, the notice now read.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), RoutePaths.staffAlerts);
  });

  testWidgets('with none yet, it says what will appear', (tester) async {
    await RequestorHarness().pump(tester, start: RoutePaths.staffAlerts);

    expect(find.textContaining('No notifications yet'), findsOneWidget);
    expect(find.text('Mark all as read'), findsNothing);
  });

  testWidgets('a failed read says so and can be retried', (tester) async {
    final app = withNotices();
    app.notifications.failure = const NetworkFailure(
      'Cannot reach the server.',
    );
    await app.pump(tester, start: RoutePaths.staffAlerts);

    expect(find.textContaining('Cannot reach the server.'), findsOneWidget);

    app.notifications.failure = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('was approved'), findsOneWidget);
  });

  testWidgets('the header bell opens Alerts', (tester) async {
    await withNotices().pump(tester);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(currentPath(tester), RoutePaths.staffAlerts);
  });

  group('permission', () {
    testWidgets('allowed: no prompt', (tester) async {
      await withNotices().pump(tester, start: RoutePaths.staffAlerts);

      expect(find.text('Allow'), findsNothing);
      expect(find.text('Open settings'), findsNothing);
    });

    testWidgets('refused: the list still works, and Allow asks again', (
      tester,
    ) async {
      final app = withNotices();
      app.push
        ..permission = PushPermission.denied
        ..answerWhenAsked = PushPermission.denied;
      await app.pump(tester, start: RoutePaths.staffAlerts);

      // In-app notifications do not depend on the phone's permission.
      expect(find.textContaining('was approved'), findsOneWidget);
      expect(find.textContaining('Allow notifications'), findsOneWidget);
      final asked = app.push.requests;

      app.push.answerWhenAsked = PushPermission.granted;
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(app.push.requests, asked + 1);
      expect(find.text('Allow'), findsNothing);
    });

    testWidgets('refused for good: Open settings', (tester) async {
      final app = withNotices();
      app.push.permission = PushPermission.permanentlyDenied;
      await app.pump(tester, start: RoutePaths.staffAlerts);

      expect(find.textContaining("phone's settings"), findsOneWidget);
      expect(find.textContaining('was approved'), findsOneWidget);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(app.push.settingsOpened, 1);
      // Never prompted: Android would not show it anyway.
      expect(app.push.requests, 0);
    });
  });
}
