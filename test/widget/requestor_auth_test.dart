import 'dart:async';

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

    testWidgets('the password field has an eye that shows and hides it', (
      tester,
    ) async {
      await RequestorHarness(signedIn: null).pump(tester);
      await tester.enterText(field('••••••••'), 'Secret#2026');

      TextField password() => tester.widget<TextField>(field('••••••••'));
      expect(password().obscureText, isTrue);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(password().obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
      // What was typed is still there, and nothing was submitted.
      expect(password().controller!.text, 'Secret#2026');

      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(password().obscureText, isTrue);
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

    Future<void> chooseDepartment(WidgetTester tester, String name) async {
      final dropdown = find.byKey(const ValueKey('sign-up-department'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    Future<void> fillIn(
      WidgetTester tester, {
      String name = 'Liza Mae Tan',
      String email = 'Liza.Tan@dorsu.edu.ph',
      String? department = 'Faculty of Business and Management',
      String password = 'Correct-horse1',
      String? confirm,
    }) async {
      await tester.enterText(field('e.g. Juan Dela Cruz'), name);
      await tester.enterText(field('juan.dc@dorsu.edu.ph'), email);
      if (department != null) await chooseDepartment(tester, department);
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
        'DEPARTMENT / FACULTY',
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

      await fillIn(
        tester,
        email: 'liza@dorsu',
        department: null,
        password: 'short',
        confirm: 'other',
      );
      await register(tester);

      expect(
        find.text('Enter a valid email address, such as juan.dc@dorsu.edu.ph.'),
        findsOneWidget,
      );
      expect(find.text('Choose your department or faculty.'), findsOneWidget);
      expect(
        find.text(
          'Your password still needs: at least 8 characters, an uppercase '
          r'letter (A–Z), a number (0–9), a special character, such as ! @ # '
          r'$ %.',
        ),
        findsOneWidget,
      );
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
      expect(profile.department, 'Faculty of Business and Management');
      expect(profile.contactNumber, isNull);

      expect(currentPath(tester), RoutePaths.staffLogin);
      expect(find.textContaining('must approve it'), findsOneWidget);
    });

    testWidgets('the department list is the one kept in Settings: active '
        'ones only', (tester) async {
      final app = await openSignUp(tester);
      final dropdown = find.byKey(const ValueKey('sign-up-department'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      expect(
        find.text('Faculty of Computing, Engineering and Technology').last,
        findsOneWidget,
      );
      expect(find.text('General Services Unit').last, findsOneWidget);
      expect(find.text('Old Office'), findsNothing, reason: 'retired');
      await tester.tap(find.text('General Services Unit').last);
      await tester.pumpAndSettle();

      await fillIn(tester, department: null);
      await register(tester);

      expect(app.users.created.single.department, 'General Services Unit');
    });

    testWidgets('with no departments on the list yet, it says so, and none '
        'is asked for', (tester) async {
      final app = RequestorHarness(signedIn: null);
      for (final department in app.departments.all) {
        await app.departments.setActive(department.id, active: false);
      }
      await app.pump(tester, start: RoutePaths.staffSignUp);

      // Said as what it is, not as a failure.
      expect(find.text('DEPARTMENT / FACULTY'), findsOneWidget);
      expect(find.text('No departments listed yet'), findsOneWidget);
      expect(
        find.text(
          'GSU has not listed any departments or faculties yet. You can '
          'create your account without one.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      await fillIn(tester, department: null);
      await register(tester);

      expect(app.users.created.single.department, isNull);
    });

    testWidgets('the requirements under the password tick off as it is '
        'typed, and both password fields have the eye', (tester) async {
      final semantics = tester.ensureSemantics();
      await openSignUp(tester);

      Finder met(String label) => find.bySemanticsLabel('$label: met');
      Finder notYet(String label) => find.bySemanticsLabel('$label: not yet');

      // At rest the form fits the phone; the list comes with the typing.
      expect(notYet('At least 8 characters'), findsNothing);

      await tester.enterText(field('••••••••').at(0), 'g');
      await tester.pump();
      expect(notYet('At least 8 characters'), findsOneWidget);
      expect(notYet('An uppercase letter (A–Z)'), findsOneWidget);
      expect(met('A lowercase letter (a–z)'), findsOneWidget);

      await tester.enterText(field('••••••••').at(0), 'Gsuhub');
      await tester.pump();
      expect(notYet('At least 8 characters'), findsOneWidget);
      expect(met('An uppercase letter (A–Z)'), findsOneWidget);
      expect(met('A lowercase letter (a–z)'), findsOneWidget);
      expect(notYet('A number (0–9)'), findsOneWidget);

      await tester.enterText(field('••••••••').at(0), 'Gsuhub#2026');
      await tester.pump();
      for (final rule in [
        'At least 8 characters',
        'An uppercase letter (A–Z)',
        'A lowercase letter (a–z)',
        'A number (0–9)',
        r'A special character, such as ! @ # $ %',
      ]) {
        expect(met(rule), findsOneWidget, reason: rule);
      }

      expect(find.byTooltip('Show password'), findsNWidgets(2));
      semantics.dispose();
    });

    testWidgets('while the list loads, a spinner says so', (tester) async {
      final app = RequestorHarness(signedIn: null);
      app.departments.holdReads = Completer<void>();
      await app.pump(tester, start: RoutePaths.staffSignUp, settle: false);
      await tester.pump();

      expect(find.text('Loading departments…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sign-up-department')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      app.departments.holdReads!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Loading departments…'), findsNothing);
      expect(find.text('Choose your department or faculty'), findsOneWidget);
    });

    testWidgets('a list that cannot be read says why, and Retry reads it '
        'again', (tester) async {
      final app = RequestorHarness(signedIn: null);
      // What the live project answered on 2026-11-17, before its database
      // had the departments table: not found, a server failure.
      app.departments.readFailure = const ServerFailure(
        "Could not find the table 'public.departments' in the schema cache",
      );
      await app.pump(tester, start: RoutePaths.staffSignUp);

      expect(find.text('Departments unavailable'), findsOneWidget);
      expect(
        find.textContaining(
          'The list of departments is not available right now.',
        ),
        findsOneWidget,
      );
      // The database's wording is not shown to the person signing up.
      expect(find.textContaining('schema cache'), findsNothing);
      expect(app.departments.reads, 1);

      // Still down: Retry asks again, and says so again.
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(app.departments.reads, 2);
      expect(find.text('Departments unavailable'), findsOneWidget);

      // Back: Retry loads it, and a department can be chosen and saved.
      app.departments.readFailure = null;
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(app.departments.reads, 3);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Choose your department or faculty'), findsOneWidget);

      await fillIn(tester);
      await register(tester);
      expect(
        app.users.created.single.department,
        'Faculty of Business and Management',
      );
    });

    testWidgets('no connection: the connection is what it names', (
      tester,
    ) async {
      final app = RequestorHarness(signedIn: null);
      app.departments.readFailure = const NetworkFailure(
        'Cannot reach the server. Check your internet connection and try '
        'again.',
      );
      await app.pump(tester, start: RoutePaths.staffSignUp);

      expect(
        find.text(
          'Cannot reach the server. Check your internet connection and try '
          'again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
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
