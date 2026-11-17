import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/utils/account_validation.dart';

/// The checks on an account's details (2026-11-17), and that the app and
/// the database hold the same patterns.
void main() {
  group('email', () {
    test('accepts an address, and says what is wrong with anything else', () {
      expect(AccountValidation.email('juan.dc@dorsu.edu.ph'), isNull);
      expect(AccountValidation.email('  Juan.DC@dorsu.edu.ph '), isNull);
      expect(AccountValidation.email(''), 'Enter your email address.');
      expect(
        AccountValidation.email('', missing: 'Enter their email address.'),
        'Enter their email address.',
      );
      for (final bad in [
        'juan',
        'juan@dorsu',
        'juan dc@dorsu.edu.ph',
        '@x.ph',
      ]) {
        expect(
          AccountValidation.email(bad),
          'Enter a valid email address, such as juan.dc@dorsu.edu.ph.',
          reason: bad,
        );
      }
    });
  });

  group('mobile number', () {
    test('is optional', () {
      expect(AccountValidation.contactNumber(null), isNull);
      expect(AccountValidation.contactNumber('   '), isNull);
    });

    test('accepts 09 and +639 numbers, spaces and dashes allowed', () {
      for (final good in [
        '09171234567',
        '0917 123 4567',
        '0917-123-4567',
        '+639171234567',
        '+63 917 123 4567',
      ]) {
        expect(AccountValidation.contactNumber(good), isNull, reason: good);
      }
      expect(
        AccountValidation.compactNumber('+63 917-123 4567'),
        '+639171234567',
      );
    });

    test('refuses anything else', () {
      for (final bad in [
        '0917123456',
        '091712345678',
        '9171234567',
        '08171234567',
        '+63817123456',
        '(02) 8123 4567',
        'none',
      ]) {
        expect(
          AccountValidation.contactNumber(bad),
          startsWith('Enter a Philippine mobile number'),
          reason: bad,
        );
      }
    });
  });

  group('password policy', () {
    test('lists the five requirements, in order', () {
      expect(PasswordPolicy.rules.map((rule) => rule.label), [
        'At least 8 characters',
        'An uppercase letter (A–Z)',
        'A lowercase letter (a–z)',
        'A number (0–9)',
        r'A special character, such as ! @ # $ %',
      ]);
    });

    test('ticks each off as it is met', () {
      expect(PasswordPolicy.unmet(''), hasLength(5));
      expect(
        PasswordPolicy.unmet('abc').map((rule) => rule.label),
        isNot(contains('A lowercase letter (a–z)')),
      );
      expect(PasswordPolicy.unmet('Abcdefg1'), hasLength(1));
      expect(PasswordPolicy.unmet('Abcdefg1!'), isEmpty);
      // A space is not a special character.
      expect(
        PasswordPolicy.unmet('Abcdefg1 ').single.label,
        contains('special'),
      );
    });

    test('says what a password still needs', () {
      expect(PasswordPolicy.validate(''), 'Choose a password.');
      expect(
        PasswordPolicy.validate('abcdefgh'),
        r'Your password still needs: an uppercase letter (A–Z), a number '
        r'(0–9), a special character, such as ! @ # $ %.',
      );
      expect(PasswordPolicy.validate('Gsuhub#2026'), isNull);
    });
  });

  test('the database checks the same patterns', () {
    final migration = File(
      'supabase/migrations/20261117102846_account_sessions_and_departments.sql',
    ).readAsStringSync();
    expect(migration, contains(r"'^[^@\s]+@[^@\s]+\.[^@\s]+$'"));
    expect(migration, contains(r"'^(09|\+639)[0-9]{9}$'"));
    expect(
      AccountValidation.emailPattern.pattern,
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    );
    expect(AccountValidation.mobilePattern.pattern, r'^(09|\+639)\d{9}$');
  });
}
