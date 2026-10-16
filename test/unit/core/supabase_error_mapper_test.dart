import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/errors/supabase_error_mapper.dart';
import 'package:gsuhub/core/services/supabase/supabase_call_guard.dart';
import 'package:gsuhub/core/services/supabase/supabase_session.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import '../../support/test_app_config.dart';

PostgrestException _postgrest(String code, [String message = 'message']) =>
    PostgrestException(message: message, code: code);

void main() {
  group('database errors', () {
    test("the database functions' own refusals are shown as written", () {
      expect(
        SupabaseErrorMapper.map(
          _postgrest('PT409', 'Only 14 units of LED Bulbs in stock.'),
        ),
        isA<ValidationFailure>().having(
          (f) => f.message,
          'message',
          'Only 14 units of LED Bulbs in stock.',
        ),
      );
      expect(
        SupabaseErrorMapper.map(_postgrest('PT403', 'Not your report.')),
        isA<PermissionFailure>().having(
          (f) => f.message,
          'message',
          'Not your report.',
        ),
      );
      expect(
        SupabaseErrorMapper.map(_postgrest('PT404')),
        isA<NotFoundFailure>(),
      );
      expect(
        SupabaseErrorMapper.map(_postgrest('PT422')),
        isA<ValidationFailure>(),
      );
    });

    test('row level security and missing grants are a permission failure', () {
      expect(
        SupabaseErrorMapper.map(_postgrest('42501', 'permission denied')),
        isA<PermissionFailure>().having(
          (f) => f.message,
          'message',
          'You do not have permission to perform this action.',
        ),
      );
    });

    test('an expired or bad token asks to sign in again', () {
      for (final code in ['PGRST301', 'PGRST303']) {
        expect(
          SupabaseErrorMapper.map(_postgrest(code)),
          isA<PermissionFailure>().having(
            (f) => f.message,
            'message',
            contains('sign in again'),
          ),
        );
      }
    });

    test(
      'constraint violations are validation failures, worded for people',
      () {
        expect(
          SupabaseErrorMapper.map(_postgrest('23505')),
          isA<ValidationFailure>(),
        );
        expect(
          SupabaseErrorMapper.map(
            _postgrest('23514', 'new row violates check constraint "x"'),
          ),
          isA<ValidationFailure>().having(
            (f) => f.message,
            'message',
            isNot(contains('constraint')),
          ),
        );
      },
    );

    test('no row for .single() is not found', () {
      expect(
        SupabaseErrorMapper.map(_postgrest('PGRST116')),
        isA<NotFoundFailure>(),
      );
    });

    test('only transient database errors are retried', () {
      for (final code in ['40001', '40P01', 'PGRST001', '503']) {
        expect(SupabaseErrorMapper.isRetryable(_postgrest(code)), isTrue);
      }
      for (final code in ['42501', 'PT409', '23505', 'PGRST116']) {
        expect(SupabaseErrorMapper.isRetryable(_postgrest(code)), isFalse);
      }
    });
  });

  group('storage errors', () {
    test("the bucket's limits are explained", () {
      expect(
        SupabaseErrorMapper.map(
          const StorageException(
            'The object exceeded the maximum allowed size',
            statusCode: '413',
          ),
        ),
        isA<ValidationFailure>().having(
          (f) => f.message,
          'message',
          'That photo is larger than 10 MB.',
        ),
      );
      expect(
        SupabaseErrorMapper.map(
          const StorageException(
            'mime type application/pdf is not supported',
            statusCode: '400',
          ),
        ),
        isA<ValidationFailure>().having(
          (f) => f.message,
          'message',
          'Only photos can be uploaded.',
        ),
      );
    });

    test('a policy refusal is a permission failure', () {
      expect(
        SupabaseErrorMapper.map(
          const StorageException(
            'new row violates row-level security policy',
            statusCode: '403',
          ),
        ),
        isA<PermissionFailure>(),
      );
    });

    test('a failed connection is offline, and worth retrying', () {
      const error = StorageException(
        'ClientException: Failed to fetch',
        statusCode: 'ClientException',
      );
      expect(SupabaseErrorMapper.map(error), isA<NetworkFailure>());
      expect(SupabaseErrorMapper.isRetryable(error), isTrue);
    });
  });

  group('the token exchange and the network', () {
    test(
      'a refused Firebase token asks to sign in again; an outage does not',
      () {
        expect(
          SupabaseErrorMapper.map(
            const SupabaseSessionException('expired', rejected: true),
          ),
          isA<PermissionFailure>(),
        );
        const outage = SupabaseSessionException('down', rejected: false);
        expect(SupabaseErrorMapper.map(outage), isA<NetworkFailure>());
        expect(SupabaseErrorMapper.isRetryable(outage), isTrue);
      },
    );

    test('timeouts and dropped connections are network failures', () {
      expect(
        SupabaseErrorMapper.map(TimeoutException('slow')),
        isA<NetworkFailure>(),
      );
      expect(
        SupabaseErrorMapper.map(http.ClientException('Connection refused')),
        isA<NetworkFailure>(),
      );
    });

    test('anything unrecognised is still a handled failure', () {
      expect(SupabaseErrorMapper.map(StateError('?')), isA<UnknownFailure>());
    });
  });

  group('SupabaseCallGuard', () {
    test('retries a dropped connection, then succeeds', () async {
      final guard = SupabaseCallGuard(testAppConfig(maxRetryAttempts: 2));
      var attempts = 0;
      final result = await guard.call(() async {
        attempts++;
        if (attempts == 1) throw http.ClientException('reset');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(attempts, 2);
    });

    test('does not retry a refusal', () async {
      final guard = SupabaseCallGuard(testAppConfig(maxRetryAttempts: 2));
      var attempts = 0;
      final result = await guard.call<void>(() async {
        attempts++;
        throw _postgrest('PT409', 'The count matches the record: 11 units.');
      });
      expect(attempts, 1);
      expect(
        result.fold((_) => null, (failure) => failure),
        isA<ValidationFailure>(),
      );
    });
  });
}
