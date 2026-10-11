import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/utils/result.dart';

import '../support/fake_requestor_app.dart';

/// Faculty and staff sign-in and sign-up (Figma `193:310`, `194:455`,
/// Objective 3.A) inside the real app and router.
void main() {
  Finder field(String hint) => find.widgetWithText(TextField, hint);

  group('sign-in', () {
    testWidgets("shows the design's card", (tester) async {
      await RequestorHarness(signedIn: null).pump(tester);

      expect(currentPath(tester), RoutePaths.staffLogin);
      expect(find.text('DAVAO ORIENTAL STATE UNIVERSITY'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      // "Username" in the design: Firebase signs in by email.
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('LOGIN TO DASHBOARD'), findsOneWidget);
      expect(find.text('CREATE ACCOUNT'), findsOneWidget);
    });

    testWidgets('an empty form says what is missing and signs nobody in', (
      tester,
    ) async {
      final app = RequestorHarness(signedIn: null);
      await app.pump(tester);

      await tester.tap(find.text('LOGIN TO DASHBOARD'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(app.auth.signInCalls, 0);
    });

    testWidgets('a requestor who signs in lands on their home screen', (
      tester,
    ) async {
      final app = RequestorHarness(signedIn: null);
      await app.pump(tester);

      await tester.enterText(
        field('e.g. juan.dc@dorsu.edu.ph'),
        'faculty@dorsu.edu.ph',
      );
      await tester.enterText(field('••••••••'), 'password123');
      await tester.tap(find.text('LOGIN TO DASHBOARD'));
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffHome);
      expect(find.text('Hello, Maria Santos'), findsOneWidget);
    });

    testWidgets('an account awaiting approval is told so, and stays out', (
      tester,
    ) async {
      final app = RequestorHarness(signedIn: null);
      app.auth.signInResult = const Result.failure(
        PermissionFailure(
          'Your account is waiting for approval by the GSU administrator. '
          'You can sign in once it has been approved.',
        ),
      );
      await app.pump(tester);

      await tester.enterText(
        field('e.g. juan.dc@dorsu.edu.ph'),
        'new.faculty@dorsu.edu.ph',
      );
      await tester.enterText(field('••••••••'), 'password123');
      await tester.tap(find.text('LOGIN TO DASHBOARD'));
      await tester.pumpAndSettle();

      expect(find.textContaining('waiting for approval'), findsOneWidget);
      expect(currentPath(tester), RoutePaths.staffLogin);
    });

    testWidgets('a wrong password gets the deliberately vague message', (
      tester,
    ) async {
      final app = RequestorHarness(signedIn: null);
      app.auth.signInResult = const Result.failure(
        PermissionFailure('Incorrect email or password.'),
      );
      await app.pump(tester);

      await tester.enterText(
        field('e.g. juan.dc@dorsu.edu.ph'),
        'faculty@dorsu.edu.ph',
      );
      await tester.enterText(field('••••••••'), 'wrong');
      await tester.tap(find.text('LOGIN TO DASHBOARD'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect email or password.'), findsOneWidget);
    });

    testWidgets('CREATE ACCOUNT opens the sign-up', (tester) async {
      await RequestorHarness(signedIn: null).pump(tester);

      await tester.tap(find.text('CREATE ACCOUNT'));
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.staffSignUp);
      expect(find.text('Create Account'), findsOneWidget);
    });
  });

  group('sign-up', () {
    Future<RequestorHarness> openSignUp(WidgetTester tester) async {
      final app = RequestorHarness(signedIn: null);
      await app.pump(tester, start: RoutePaths.staffSignUp);
      return app;
    }

    Future<void> fillIn(
      WidgetTester tester, {
      String name = 'Liza Mae Tan',
      String email = 'Liza.Tan@dorsu.edu.ph',
      String password = 'correct-horse',
      String? confirm,
    }) async {
      await tester.enterText(field('e.g. Juan Dela Cruz'), name);
      await tester.enterText(field('juan.dc@dorsu.edu.ph'), email);
      await tester.enterText(field('••••••••').at(0), password);
      await tester.enterText(field('••••••••').at(1), confirm ?? password);
    }

    Future<void> register(WidgetTester tester) async {
      await tester.ensureVisible(find.text('REGISTER'));
      await tester.tap(find.text('REGISTER'));
      await tester.pumpAndSettle();
    }

    testWidgets("shows the design's fields", (tester) async {
      await openSignUp(tester);

      for (final label in [
        'Create Account',
        'Create An Account and Report',
        'FULL NAME',
        'EMAIL',
        'PASSWORD',
        'CONFIRM PASSWORD',
        'REGISTER',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('an incomplete form marks each problem and sends nothing', (
      tester,
    ) async {
      final app = await openSignUp(tester);

      await fillIn(tester, password: 'short', confirm: 'other');
      await register(tester);

      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(app.auth.registered, isEmpty);
    });

    testWidgets('a complete form files a request and returns to sign-in', (
      tester,
    ) async {
      final app = await openSignUp(tester);

      await fillIn(tester);
      await register(tester);

      expect(app.auth.registered, ['liza.tan@dorsu.edu.ph']);
      final profile = app.users.created.single;
      expect(profile.role, UserRole.requestor);
      expect(profile.accountStatus, AccountStatus.pending);

      expect(currentPath(tester), RoutePaths.staffLogin);
      expect(find.textContaining('must approve it'), findsOneWidget);
    });

    testWidgets('an address already in use is reported', (tester) async {
      final app = await openSignUp(tester);
      app.auth.registerResult = const Result.failure(
        ValidationFailure('An account already exists for that email address.'),
      );

      await fillIn(tester);
      await register(tester);

      expect(
        find.text('An account already exists for that email address.'),
        findsOneWidget,
      );
      expect(currentPath(tester), RoutePaths.staffSignUp);
    });

    testWidgets('a signed-in requestor is moved past the sign-up', (
      tester,
    ) async {
      await RequestorHarness().pump(tester, start: RoutePaths.staffSignUp);

      expect(currentPath(tester), RoutePaths.staffHome);
    });
  });
}
