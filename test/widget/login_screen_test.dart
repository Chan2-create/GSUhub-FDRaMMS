import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/auth/presentation/login_screen.dart';

/// Login form behaviour (Objective 2.A).
///
/// Drives a fake [AuthService] rather than Firebase — the point is the
/// form's validation and error handling, and a test that needed a live
/// backend would be testing Firebase instead.
void main() {
  late _FakeAuthService auth;

  setUp(() => auth = _FakeAuthService());

  /// The admin console is a desktop-web screen designed at 1440x1024. The
  /// 800x600 default test surface pushes the LOGIN button below the fold,
  /// where it cannot be tapped — so the viewport is sized to match the
  /// platform the screen actually targets.
  Future<void> pumpLogin(WidgetTester tester, {String? redirectTo}) async {
    tester.view
      ..physicalSize = const Size(1440, 1024)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A real router, because a successful sign-in calls `context.go` —
    // with a plain MaterialApp that throws, and the test would be
    // asserting against a crash rather than the behaviour.
    final router = GoRouter(
      initialLocation: RoutePaths.adminLogin,
      routes: [
        GoRoute(
          path: RoutePaths.adminLogin,
          builder: (context, state) => LoginScreen(redirectTo: redirectTo),
        ),
        GoRoute(
          path: RoutePaths.adminDashboard,
          builder: (context, state) => const Text('DASHBOARD'),
        ),
        GoRoute(
          path: RoutePaths.adminReports,
          builder: (context, state) => const Text('REPORTS'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'LOGIN'));
    await tester.pumpAndSettle();
  }

  group('layout', () {
    testWidgets('shows the designed copy', (tester) async {
      await pumpLogin(tester);

      expect(find.text('Welcome back!'), findsOneWidget);
      expect(find.text('Forget password?'), findsOneWidget);
      expect(find.text('DAVAO ORIENTAL STATE\nUNIVERSITY'), findsOneWidget);
    });

    testWidgets('has no sign-up link — accounts are provisioned', (
      tester,
    ) async {
      await pumpLogin(tester);

      // Manuscript §1.5 limits access to authorized accounts; an admin
      // console that let anyone register would contradict that.
      expect(find.textContaining('Sign up'), findsNothing);
      expect(find.textContaining('Create account'), findsNothing);
    });

    testWidgets('labels the identifier field Email, not Username', (
      tester,
    ) async {
      await pumpLogin(tester);

      // Deviation from Figma, made deliberately: Firebase Auth signs in
      // with an email address, and a field labelled "Username" would
      // reject a username with an error the user cannot act on.
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Username'), findsNothing);
    });
  });

  group('validation', () {
    testWidgets('rejects an empty submission without calling the service', (
      tester,
    ) async {
      await pumpLogin(tester);
      await submit(tester);

      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(auth.signInCallCount, 0);
    });

    testWidgets('rejects a malformed email', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await submit(tester);

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(auth.signInCallCount, 0);
    });

    testWidgets('accepts a well-formed email and signs in', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'admin@dorsu.edu.ph',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await submit(tester);

      expect(auth.signInCallCount, 1);
      expect(auth.lastEmail, 'admin@dorsu.edu.ph');
      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    testWidgets('forwards to the originally requested route', (tester) async {
      // The guard records where an unauthenticated user was headed; a
      // successful sign-in must land there rather than the dashboard.
      await pumpLogin(tester, redirectTo: RoutePaths.adminReports);

      await tester.enterText(
        find.byType(TextFormField).first,
        'admin@dorsu.edu.ph',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await submit(tester);

      expect(find.text('REPORTS'), findsOneWidget);
    });
  });

  group('error handling', () {
    testWidgets('surfaces a wrong-credentials message', (tester) async {
      auth.signInResult = const Result.failure(
        PermissionFailure('Incorrect email or password.'),
      );
      await pumpLogin(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'admin@dorsu.edu.ph',
      );
      await tester.enterText(find.byType(TextFormField).last, 'wrong');
      await submit(tester);

      expect(find.text('Incorrect email or password.'), findsOneWidget);
    });

    testWidgets('surfaces a deactivated-account message distinctly', (
      tester,
    ) async {
      const message =
          'This account is not authorized to use GSUhub, or has been '
          'deactivated. Contact the GSU administrator.';
      auth.signInResult = const Result.failure(PermissionFailure(message));
      await pumpLogin(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'former@dorsu.edu.ph',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await submit(tester);

      // Distinct from "wrong password" so a deactivated user stops
      // retrying their perfectly correct credentials.
      expect(find.text(message), findsOneWidget);
    });

    testWidgets('surfaces a network failure distinctly', (tester) async {
      auth.signInResult = const Result.failure(
        NetworkFailure('Cannot reach the server.'),
      );
      await pumpLogin(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'admin@dorsu.edu.ph',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await submit(tester);

      expect(find.text('Cannot reach the server.'), findsOneWidget);
    });
  });

  group('password reset', () {
    testWidgets('opens a dialog prefilled with the typed email', (
      tester,
    ) async {
      await pumpLogin(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'admin@dorsu.edu.ph',
      );
      await tester.tap(find.text('Forget password?'));
      await tester.pumpAndSettle();

      expect(find.text('Reset your password'), findsOneWidget);
      // Scoped to the dialog: the login field still holds the same text,
      // so an unscoped finder would match twice.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('admin@dorsu.edu.ph'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sends the reset and confirms without confirming the '
        'account exists', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'someone@dorsu.edu.ph',
      );
      await tester.tap(find.text('Forget password?'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
      await tester.pumpAndSettle();

      expect(auth.resetCallCount, 1);
      // Deliberately ambiguous: confirming which addresses have accounts
      // would turn this form into an account-enumeration oracle.
      expect(find.textContaining('If an account exists'), findsOneWidget);
    });
  });
}

class _FakeAuthService implements AuthService {
  Result<AuthUser> signInResult = const Result.success(
    AuthUser(uid: 'admin-1', email: 'admin@dorsu.edu.ph', role: UserRole.admin),
  );

  int signInCallCount = 0;
  int resetCallCount = 0;
  String? lastEmail;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<Result<AuthUser>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signInCallCount++;
    lastEmail = email;
    return signInResult;
  }

  @override
  Future<Result<void>> sendPasswordResetEmail({required String email}) async {
    resetCallCount++;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> signOut() async => const Result.success(null);
}
