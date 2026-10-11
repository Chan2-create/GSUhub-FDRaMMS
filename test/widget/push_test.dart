import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/services/notification_service.dart';
import 'package:gsuhub/core/utils/result.dart';

import '../support/fake_notifications.dart';
import '../support/fake_requestor_app.dart';

/// The phone's side of notifications (Objective 3.B): the token, the
/// permission, notices raised while the app runs, and taps that open a
/// report — inside the real app, over a fake push service.
void main() {
  RequestorHarness app({List<String> unread = const []}) => RequestorHarness(
    reports: [fakeMyReport('r-newest')],
    notices: [for (final id in unread) fakeNotice(id)],
  );

  Future<void> signOut(WidgetTester tester) async {
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
  }

  group('token', () {
    testWidgets('signing in saves the device token on the account', (
      tester,
    ) async {
      final harness = app();
      await harness.pump(tester);

      expect(harness.users.tokens, ['device-token-1']);
    });

    testWidgets('a rotated token is saved again', (tester) async {
      final harness = app();
      await harness.pump(tester);

      harness.push.rotate('device-token-2');
      await tester.pumpAndSettle();

      expect(harness.users.tokens, ['device-token-1', 'device-token-2']);
    });

    testWidgets('signing out clears it from the account and the phone', (
      tester,
    ) async {
      final harness = app();
      await harness.pump(tester);

      await signOut(tester);

      expect(harness.users.tokens, ['device-token-1', null]);
      expect(harness.push.tokensDeleted, 1);
      expect(currentPath(tester), RoutePaths.staffLogin);
    });

    testWidgets('a phone with no token saves nothing', (tester) async {
      final harness = app();
      harness.push.token = null;
      await harness.pump(tester);

      expect(harness.users.tokens, isEmpty);
    });
  });

  group('permission', () {
    testWidgets('asked once on sign-in while Android will still prompt', (
      tester,
    ) async {
      final harness = app();
      harness.push
        ..permission = PushPermission.denied
        ..answerWhenAsked = PushPermission.granted;
      await harness.pump(tester);

      expect(harness.push.requests, 1);
    });

    testWidgets('not asked when already allowed', (tester) async {
      final allowed = app();
      await allowed.pump(tester);
      expect(allowed.push.requests, 0);
    });

    testWidgets('not asked once Android has stopped prompting', (tester) async {
      final refused = app();
      refused.push.permission = PushPermission.permanentlyDenied;
      await refused.pump(tester);
      expect(refused.push.requests, 0);
    });
  });

  group('notices while the app runs', () {
    testWidgets('a new one is raised on the phone; the old ones are not', (
      tester,
    ) async {
      final harness = app(unread: ['n-old']);
      await harness.pump(tester);
      expect(harness.push.shown, isEmpty);

      harness.notifications.deliver(
        fakeNotice(
          'n-new',
          title: 'Work started',
          body: 'Work has started on your report "Broken ceiling fan".',
        ),
      );
      await tester.pumpAndSettle();

      expect(harness.push.shown, hasLength(1));
      final shown = harness.push.shown.single;
      expect(shown.title, 'Work started');
      expect(shown.payload['reportId'], 'r-newest');
      expect(shown.payload['notificationId'], 'n-new');
    });

    testWidgets('a push in the foreground is shown once, not twice', (
      tester,
    ) async {
      final harness = app();
      await harness.pump(tester);

      harness.notifications.deliver(fakeNotice('n-1'));
      await tester.pumpAndSettle();
      // The same notice pushed by a server (once on Blaze).
      harness.push.receive({
        'notificationId': 'n-1',
        'reportId': 'r-newest',
        'title': 'Report approved',
        'body': 'Your report was approved.',
      });
      await tester.pumpAndSettle();
      expect(harness.push.shown, hasLength(1));

      harness.push.receive({
        'notificationId': 'n-2',
        'reportId': 'r-newest',
        'title': 'Work started',
        'body': 'Work has started.',
      });
      await tester.pumpAndSettle();
      expect(harness.push.shown, hasLength(2));
    });

    testWidgets('after signing out, nothing more is raised', (tester) async {
      final harness = app();
      await harness.pump(tester);
      await signOut(tester);

      harness.notifications.deliver(fakeNotice('n-late'));
      await tester.pumpAndSettle();

      expect(harness.push.shown, isEmpty);
    });
  });

  group('tapping a notification', () {
    testWidgets('opens its report and marks it read', (tester) async {
      final harness = app(unread: ['n-1']);
      await harness.pump(tester);

      harness.push.tap({
        'notificationId': 'n-1',
        'reportId': 'r-newest',
        'recipientId': fakeRequestor.uid,
      });
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffReportDetailFor('r-newest'));
      expect(harness.notifications.markedRead, ['n-1']);
    });

    testWidgets('that launched the app from closed opens its report', (
      tester,
    ) async {
      final harness = app(unread: ['n-1']);
      harness.push.launch = {
        'notificationId': 'n-1',
        'reportId': 'r-newest',
        'recipientId': fakeRequestor.uid,
      };
      await harness.pump(tester);

      expect(currentPath(tester), RoutePaths.staffReportDetailFor('r-newest'));
    });

    testWidgets('addressed to another account, it is not opened', (
      tester,
    ) async {
      final harness = app();
      await harness.pump(tester);

      harness.push.tap({
        'notificationId': 'n-x',
        'reportId': 'r-theirs',
        'recipientId': 'faculty-2',
      });
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffHome);
      expect(harness.notifications.markedRead, isEmpty);
    });
  });

  testWidgets('the next account on the phone gets only its own', (
    tester,
  ) async {
    final harness = app();
    await harness.pump(tester);
    await signOut(tester);

    // Somebody else signs in on the same phone.
    const other = AuthUser(
      uid: 'faculty-2',
      email: 'ana.gomez@dorsu.edu.ph',
      role: UserRole.requestor,
    );
    harness.auth.signInResult = const Result.success(other);
    await harness.auth.signInWithEmailAndPassword(
      email: other.email,
      password: 'password123',
    );
    await tester.pumpAndSettle();

    // A notice for the first account lands: nothing on this phone.
    harness.notifications.deliver(fakeNotice('n-first'));
    await tester.pumpAndSettle();
    expect(harness.push.shown, isEmpty);

    // One for the second does.
    harness.notifications.deliver(
      fakeNotice('n-second', recipientId: other.uid),
    );
    await tester.pumpAndSettle();
    expect(harness.push.shown.map((s) => s.payload['notificationId']), [
      'n-second',
    ]);
  });
}
