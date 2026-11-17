import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/app.dart';
import 'package:gsuhub/core/config/session_policy.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/session/inactivity_monitor.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/auth/presentation/admin_login_screen.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';

import '../support/app_fonts.dart';
import '../support/fake_admin_backend.dart';
import '../support/fake_requestor_app.dart';
import '../support/fake_session.dart';

/// An administrator deactivating an account, or changing its role, signs
/// the person out wherever they are signed in, with a notice saying why
/// (2026-11-17). The app hears of it from its own account changing, and
/// from any refusal the database sends; the database is what decides
/// (supabase/tests/account_sessions.test.sql).
void main() {
  setUpAll(loadAppFonts);

  late DateTime now;
  late InactivityMonitor monitor;

  setUp(() {
    now = DateTime(2026, 11, 17, 9);
    monitor = InactivityMonitor(clock: () => now);
  });

  group('the faculty and staff app', () {
    testWidgets('signed in, the app asks where its session stands, which '
        'does not count as activity', (tester) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester);

      expect(app.sessions.stateChecks, 1, reason: 'on signing in');
      final touches = app.sessions.touches;

      // An edit that changes nothing about the session.
      app.users.accountChanged();
      await tester.pumpAndSettle();

      expect(app.sessions.stateChecks, 2);
      expect(app.sessions.touches, touches);
      expect(find.text('Home'), findsWidgets, reason: 'still signed in');
    });

    testWidgets('deactivated by an administrator: signed out at once, told '
        'why on the sign-in page', (tester) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester, start: RoutePaths.staffMyReports);

      app.sessions.stateResult = const Result.success(
        SessionEndReason.deactivated,
      );
      app.users.accountChanged();
      await tester.pumpAndSettle();

      expect(find.text('LOGIN TO DASHBOARD'), findsOneWidget);
      expect(find.text(SessionPolicy.deactivatedMessage), findsOneWidget);
      expect(find.text(SessionPolicy.endedMessage), findsNothing);
      expect(app.auth.currentUser, isNull);
      expect(monitor.isWatching, isFalse);
      expect(app.users.tokens, contains(null), reason: 'push token retired');
    });

    testWidgets('a role changed by an administrator: signed out, told to '
        'sign in again', (tester) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester);

      app.sessions.stateResult = const Result.success(
        SessionEndReason.roleChanged,
      );
      app.users.accountChanged();
      await tester.pumpAndSettle();

      expect(find.text('LOGIN TO DASHBOARD'), findsOneWidget);
      expect(find.text(SessionPolicy.roleChangedMessage), findsOneWidget);
      expect(app.auth.currentUser, isNull);
    });

    testWidgets('a refusal from the database, on any call, says the same', (
      tester,
    ) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester);

      app.sessions.touchResult = const Result.failure(
        SessionExpiredFailure(
          'Your account has been deactivated by the Administrator.',
          reason: SessionEndReason.deactivated,
        ),
      );
      // The app tells the database the person is here at most once a
      // minute, on activity.
      now = now.add(const Duration(seconds: 61));
      await tester.tapAt(const Offset(20, 300));
      await tester.pumpAndSettle();

      expect(find.text(SessionPolicy.deactivatedMessage), findsOneWidget);
    });

    testWidgets('signing in again after the notice clears it', (tester) async {
      final app = RequestorHarness(monitor: monitor);
      await app.pump(tester);
      app.sessions.stateResult = const Result.success(
        SessionEndReason.roleChanged,
      );
      app.users.accountChanged();
      await tester.pumpAndSettle();
      expect(find.text(SessionPolicy.roleChangedMessage), findsOneWidget);

      app.sessions.stateResult = const Result.success(null);
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. juan.dc@dorsu.edu.ph'),
        'faculty@dorsu.edu.ph',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '••••••••'),
        'password123',
      );
      await tester.tap(find.text('LOGIN TO DASHBOARD'));
      await tester.pumpAndSettle();

      expect(find.text(SessionPolicy.roleChangedMessage), findsNothing);
      expect(find.text('Hello, Maria Santos'), findsOneWidget);
      expect(monitor.isWatching, isTrue);
    });
  });

  group('the console', () {
    Future<FakeUserRepository> pumpConsole(
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
      final users = FakeUserRepository(
        personnel: const Result.success(<AppUser>[]),
        signedIn: fakeAdminUser,
      );
      await tester.pumpWidget(
        fakeAdminScope(
          authService: auth,
          sessions: sessions,
          monitor: monitor,
          userRepository: users,
          startLocation: start,
          child: const GsuhubApp(),
        ),
      );
      await tester.pumpAndSettle();
      return users;
    }

    testWidgets('an administrator deactivated by another is signed out, to '
        'the plain sign-in page, with the notice', (tester) async {
      final auth = ScriptedAuthService(signedIn: fakeAdminUser);
      final sessions = FakeSessionRepository();
      final users = await pumpConsole(
        tester,
        auth: auth,
        sessions: sessions,
        start: RoutePaths.adminReports,
      );
      expect(find.text('Damage Reports'), findsWidgets);

      sessions.stateResult = const Result.success(SessionEndReason.deactivated);
      users.accountChanged();
      await tester.pumpAndSettle();

      final login = find.byType(AdminLoginScreen);
      expect(login, findsOneWidget);
      expect(find.text(SessionPolicy.deactivatedMessage), findsOneWidget);
      // Not back to the page it was on: that page may be none of theirs.
      expect(tester.widget<AdminLoginScreen>(login).redirectTo, isNull);
      expect(
        GoRouter.of(tester.element(login))
            .routerDelegate
            .currentConfiguration
            .uri
            .toString(),
        RoutePaths.adminLogin,
      );
      expect(auth.currentUser, isNull);
    });

    testWidgets('a role change on the console says so too', (tester) async {
      final auth = ScriptedAuthService(signedIn: fakeAdminUser);
      final sessions = FakeSessionRepository();
      final users = await pumpConsole(tester, auth: auth, sessions: sessions);

      sessions.stateResult = const Result.success(SessionEndReason.roleChanged);
      users.accountChanged();
      await tester.pumpAndSettle();

      expect(find.byType(AdminLoginScreen), findsOneWidget);
      expect(find.text(SessionPolicy.roleChangedMessage), findsOneWidget);
    });
  });
}
