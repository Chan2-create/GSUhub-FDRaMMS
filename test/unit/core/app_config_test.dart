import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/config/app_config.dart';

import '../../support/test_app_config.dart';

/// A key shaped like Supabase's legacy JWT keys, with [role] in it. Not a
/// real key: nothing signs it.
String _legacyKey(String role) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'iss': 'supabase-demo', 'role': role})}.signature';
}

void main() {
  group('PrioritizationWeights', () {
    test('manuscript Table 3.2 defaults sum to 1.0', () {
      const weights = PrioritizationWeights();
      expect(weights.isValid, isTrue);
      expect(weights.severity, 0.40);
      expect(weights.safetyRisk, 0.30);
      expect(weights.frequency, 0.20);
      expect(weights.locationImportance, 0.10);
    });

    test('isValid is false when weights do not sum to 1.0', () {
      const weights = PrioritizationWeights(severity: 0.9);
      expect(weights.isValid, isFalse);
    });
  });

  group('supabaseConfigProblem', () {
    test('a development build on the local stack is fine', () {
      expect(
        testAppConfig(
          useEmulator: true,
          supabaseAnonKey: _legacyKey('anon'),
        ).supabaseConfigProblem,
        isNull,
      );
    });

    test('a live build on a hosted project is fine', () {
      expect(
        testAppConfig(
          supabaseUrl: 'https://abcdefgh.supabase.co',
          supabaseAnonKey: 'sb_publishable_abc123',
        ).supabaseConfigProblem,
        isNull,
      );
    });

    test('a build without the URL or the key says which is missing', () {
      expect(
        testAppConfig(supabaseUrl: '').supabaseConfigProblem,
        contains('SUPABASE_URL'),
      );
      expect(
        testAppConfig(supabaseAnonKey: '').supabaseConfigProblem,
        contains('SUPABASE_ANON_KEY'),
      );
    });

    test('the service-role or secret key is refused: it skips every rule', () {
      expect(
        testAppConfig(supabaseAnonKey: _legacyKey('service_role'))
            .supabaseConfigProblem,
        contains('must never ship'),
      );
      expect(
        testAppConfig(supabaseAnonKey: 'sb_secret_abc123')
            .supabaseConfigProblem,
        contains('must never ship'),
      );
    });

    test('the Auth emulator is never paired with a hosted database', () {
      expect(
        testAppConfig(
          useEmulator: true,
          supabaseUrl: 'https://abcdefgh.supabase.co',
        ).supabaseConfigProblem,
        contains('Auth emulator'),
      );
    });

    test('nor with something that is not a URL', () {
      expect(
        testAppConfig(supabaseUrl: 'localhost').supabaseConfigProblem,
        contains('not a URL'),
      );
    });
  });
}
