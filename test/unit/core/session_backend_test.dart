import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/errors/supabase_error_mapper.dart';
import 'package:gsuhub/core/routing/route_guards.dart';
import 'package:gsuhub/core/services/supabase/supabase_call_guard.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:supabase/supabase.dart';

import '../../support/test_app_config.dart';

/// The database's side of the session's end (2026-11-14): its refusal
/// (PT401) reaches the app as its own failure, every guarded call reports
/// it, and the sign-in page the person lands on remembers where they were.
void main() {
  const refusal = PostgrestException(
    message:
        'Your session ended after 15 minutes of inactivity. Sign in again '
        'to continue.',
    code: 'PT401',
  );

  test('PT401 is the session ending, with the database\'s own words', () {
    final failure = SupabaseErrorMapper.map(refusal);
    expect(failure, isA<SessionExpiredFailure>());
    expect(failure.message, refusal.message);
    expect(
      SupabaseErrorMapper.isRetryable(refusal),
      isFalse,
      reason: 'it fails the same way every time',
    );
  });

  test('the other refusals are what they were', () {
    expect(
      SupabaseErrorMapper.map(
        const PostgrestException(message: 'No.', code: 'PT403'),
      ),
      isA<PermissionFailure>(),
    );
    expect(
      SupabaseErrorMapper.map(
        const PostgrestException(message: 'Gone.', code: 'PT404'),
      ),
      isA<NotFoundFailure>(),
    );
  });

  group('the call guard tells of every failure it maps', () {
    late List<Failure> heard;
    late SupabaseCallGuard guard;

    setUp(() {
      heard = [];
      guard = SupabaseCallGuard(testAppConfig(), onFailure: heard.add);
    });

    test('from a call', () async {
      final result = await guard.call<void>(() async => throw refusal);
      expect(result, isA<Error<void>>());
      expect(heard, [isA<SessionExpiredFailure>()]);
    });

    test('from a call made once', () async {
      await guard.callOnce<void>(() async => throw refusal);
      expect(heard, [isA<SessionExpiredFailure>()]);
    });

    test('from a live stream', () async {
      final results = await guard
          .stream<int>(Stream<int>.error(refusal))
          .toList();
      expect(results, [isA<Error<int>>()]);
      expect(heard, [isA<SessionExpiredFailure>()]);
    });

    test('and not of success', () async {
      await guard.call(() async => 1);
      expect(heard, isEmpty);
    });
  });

  group('where a session that ended goes', () {
    test('to the area\'s sign-in page, remembering the page', () {
      expect(
        AppRouteGuard.signedOutLocationFor('/admin/reports/rep-0001'),
        '/admin/login?redirect=%2Fadmin%2Freports%2Frep-0001',
      );
      expect(
        AppRouteGuard.signedOutLocationFor('/personnel/work-orders/wo-3'),
        '/staff/login?redirect=%2Fpersonnel%2Fwork-orders%2Fwo-3',
      );
      expect(
        AppRouteGuard.signedOutLocationFor('/staff/reports'),
        '/staff/login?redirect=%2Fstaff%2Freports',
      );
    });

    test('with nothing to remember on the page sign-in opens anyway', () {
      expect(
        AppRouteGuard.signedOutLocationFor('/admin/dashboard'),
        '/admin/login',
      );
      expect(AppRouteGuard.signedOutLocationFor('/staff/home'), '/staff/login');
    });

    test('a chosen Logout goes to the sign-in page plain', () {
      expect(AppRouteGuard.loginPageFor('/admin/reports'), '/admin/login');
      expect(AppRouteGuard.loginPageFor('/personnel/alerts'), '/staff/login');
      expect(AppRouteGuard.loginPageFor('/staff/alerts'), '/staff/login');
    });
  });
}
