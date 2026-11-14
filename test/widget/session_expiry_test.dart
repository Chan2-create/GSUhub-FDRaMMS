import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/app.dart';
import 'package:gsuhub/core/config/session_policy.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/session/inactivity_monitor.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/auth/presentation/admin_login_screen.dart';

import '../support/app_fonts.dart';
import '../support/fake_admin_backend.dart';
import '../support/fake_requestor_app.dart';
import '../support/fake_session.dart';

/// Sessions end after 30 minutes without activity (2026-11-14), on the
/// phone and on the console: a warning with a countdown at 28 minutes,
/// cleared by doing anything; then signed out, on the sign-in page, which
/// says why. The database can end a session too, and the app follows.
void main() {
  setUpAll(loadAppFonts);

  late DateTime now;
  late InactivityMonitor monitor;

  setUp(() {
    now = DateTime(2026, 11, 14, 9);
    monitor = InactivityMonitor(clock: () => now);
  });

  /// Moves the clock on and lets the monitor's next tick see it.
  Future<void> elapse(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(const Duration(seconds: 1));
  }

  final warning = find.text('Still there?');

  group('the faculty and staff app', () {
    testWidgets('warns at 28 minutes with a countdown, and any tap clears it', (
      tester,
    ) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester);
      expect(
        app.sessions.touches,
        1,
        reason: 'signing in tells the database the person is here',
      );

      await elapse(tester, const Duration(minutes: 27, seconds: 58));
      expect(warning, findsNothing);

      await elapse(tester, const Duration(seconds: 2));
      expect(warning, findsOneWidget);
      expect(find.text('2:00'), findsOneWidget);
      expect(find.text('until you are signed out'), findsOneWidget);

      await elapse(tester, const Duration(seconds: 1));
      expect(find.text('1:59'), findsOneWidget);

      // A tap anywhere, even on the dimmed page, is activity.
      await tester.tapAt(const Offset(20, 300));
      await tester.pump();
      expect(warning, findsNothing);
      expect(find.text('Home'), findsWidgets, reason: 'still signed in');

      // And the clock started over: 28 more minutes before the next.
      await elapse(tester, const Duration(minutes: 27));
      expect(warning, findsNothing);
      await elapse(tester, const Duration(minutes: 1));
      expect(warning, findsOneWidget);

      await tester.tap(find.text('Stay signed in'));
      await tester.pump();
      expect(warning, findsNothing);
    });

    testWidgets('signs out at 30 minutes, saying why on the sign-in page', (
      tester,
    ) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester, start: RoutePaths.staffMyReports);

      await elapse(tester, const Duration(minutes: 30));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN TO DASHBOARD'), findsOneWidget);
      expect(find.text(SessionPolicy.endedMessage), findsOneWidget);
      expect(app.auth.currentUser, isNull);
      expect(
        app.users.tokens,
        contains(null),
        reason: 'the phone\'s push token was retired first, as Logout does',
      );
      expect(monitor.isWatching, isFalse);
    });

    testWidgets('a phone that slept past the limit is signed out on waking', (
      tester,
    ) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester);

      // No ticks: the app was in the background. Then it comes back.
      // (Inactive, not paused: the test binding stops pumping frames for a
      // paused app, and never quite resumes them.)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now = now.add(const Duration(minutes: 45));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('LOGIN TO DASHBOARD'), findsOneWidget);
      expect(find.text(SessionPolicy.endedMessage), findsOneWidget);
    });

    testWidgets('"Sign out now" on the warning is a chosen Logout', (
      tester,
    ) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester);

      await elapse(tester, const Duration(minutes: 28));
      await tester.tap(find.text('Sign out now'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN TO DASHBOARD'), findsOneWidget);
      expect(
        find.text(SessionPolicy.endedMessage),
        findsNothing,
        reason: 'they chose to leave; nothing to explain',
      );
      expect(app.auth.currentUser, isNull);
    });

    testWidgets('the database ending the session signs the app out too', (
      tester,
    ) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester);

      // Its next answer: the session was idle too long (PT401).
      app.sessions.touchResult = const Result.failure(
        SessionExpiredFailure('Your session ended.'),
      );
      // The app asks it again at most once a minute, on activity.
      now = now.add(const Duration(seconds: 61));
      await tester.tapAt(const Offset(20, 300));
      await tester.pumpAndSettle();

      expect(app.sessions.touches, 2);
      expect(find.text('LOGIN TO DASHBOARD'), findsOneWidget);
      expect(find.text(SessionPolicy.endedMessage), findsOneWidget);
    });

    testWidgets('while in use, the database hears of it once a minute', (
      tester,
    ) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester);

      for (var i = 0; i < 5; i++) {
        await tester.tapAt(const Offset(20, 300));
        now = now.add(const Duration(seconds: 10));
      }
      expect(app.sessions.touches, 1, reason: 'five taps in 50 seconds');

      now = now.add(const Duration(seconds: 15));
      await tester.tapAt(const Offset(20, 300));
      await tester.pump();
      expect(app.sessions.touches, 2);
    });
  });

  group('the console', () {
    Future<void> pumpConsole(
      WidgetTester tester, {
      required ScriptedAuthService auth,
      required FakeSessionRepository sessions,
      String? start,
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 1024)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        fakeAdminScope(
          authService: auth,
          sessions: sessions,
          monitor: monitor,
          startLocation: start,
          child: const GsuhubApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'mouse movement and keys count as activity; the warning shows over '
      'the page',
      (tester) async {
        final auth = ScriptedAuthService(signedIn: fakeAdminUser);
        await pumpConsole(
          tester,
          auth: auth,
          sessions: FakeSessionRepository(),
        );

        await elapse(tester, const Duration(minutes: 28));
        expect(warning, findsOneWidget);
        expect(find.text('2:00'), findsOneWidget);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(700, 500));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(const Offset(720, 520));
        await tester.pump();
        expect(warning, findsNothing, reason: 'the mouse moved');

        await elapse(tester, const Duration(minutes: 28));
        expect(warning, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(warning, findsNothing, reason: 'a key was pressed');
      },
    );

    testWidgets(
      'signed out at 30 minutes; signing in again returns to the page',
      (tester) async {
        final auth = ScriptedAuthService(signedIn: fakeAdminUser)
          ..signInResult = const Result.success(fakeAdminUser);
        await pumpConsole(
          tester,
          auth: auth,
          sessions: FakeSessionRepository(),
          start: RoutePaths.adminReports,
        );
        expect(find.text('Damage Reports'), findsWidgets);

        await elapse(tester, const Duration(minutes: 30));
        await tester.pumpAndSettle();

        final login = find.byType(AdminLoginScreen);
        expect(login, findsOneWidget);
        expect(find.text(SessionPolicy.endedMessage), findsOneWidget);
        expect(
          tester.widget<AdminLoginScreen>(login).redirectTo,
          RoutePaths.adminReports,
          reason: 'the page the session ended on',
        );
        expect(
          GoRouter.of(tester.element(login))
              .routerDelegate
              .currentConfiguration
              .uri
              .toString(),
          '/admin/login?redirect=%2Fadmin%2Freports',
        );
        expect(auth.currentUser, isNull);
      },
    );
  });
}
