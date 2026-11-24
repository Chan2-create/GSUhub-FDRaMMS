import 'dart:io';
import 'dart:math';

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
        '8–12 characters',
        'One uppercase letter',
        'One lowercase letter',
        'One number',
        r'One special character (e.g., @ # $ ! % &)',
      ]);
    });

    test('is one regular expression', () {
      expect(
        PasswordPolicy.pattern.pattern,
        r'^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])'
        r'''(?=.*[\^$*.\[\]{}()?"!@#%&/\\,><':;|_~])\S{8,12}$''',
      );
    });

    // The brief's cases (2026-11-25), each with what is said about it.
    final cases = <String, (bool, String?)>{
      'Ab1!xyz': (false, 'Your password still needs: 8–12 characters.'),
      'Abc1!': (false, 'Your password still needs: 8–12 characters.'),
      'Abcdefghij1!x': (false, 'Use no more than 12 characters.'),
      'abcdefg1!': (false, 'Your password still needs: one uppercase letter.'),
      'ABCDEFG1!': (false, 'Your password still needs: one lowercase letter.'),
      'Abcdefgh!': (false, 'Your password still needs: one number.'),
      'Abcdefgh1': (
        false,
        r'Your password still needs: one special character (e.g., @ # $ ! '
            '% &).',
      ),
      'Abcd efg1!': (false, 'A password cannot contain spaces.'),
      'Abcdefg1\t!': (false, 'A password cannot contain spaces.'),
      'Gsuhub#2026': (true, null),
      'Abcdefg1!': (true, null),
      'Aa1!Aa1!Aa1!': (true, null),
    };
    for (final MapEntry(key: password, value: (valid, message))
        in cases.entries) {
      test('"$password": ${valid ? 'accepted' : 'refused'}', () {
        expect(PasswordPolicy.isValid(password), valid);
        expect(PasswordPolicy.validate(password), message);
      });
    }

    test('counts only the special characters Firebase counts', () {
      for (final special in PasswordPolicy.specialCharacters.split('')) {
        expect(
          PasswordPolicy.isValid('Abcdef1$special'),
          isTrue,
          reason: special,
        );
      }
      // Allowed in a password, but not the special character it needs.
      for (final other in ['-', '+', '=', '`', 'ñ']) {
        expect(PasswordPolicy.isValid('Abcdef1$other'), isFalse, reason: other);
        expect(PasswordPolicy.isValid('Abcdef1!$other'), isTrue, reason: other);
      }
    });

    test('the list under the field and the expression always agree', () {
      // Every password of up to 14 characters drawn from a small alphabet
      // with one of each kind, a space and a character that is not special.
      const alphabet = ['A', 'a', '1', '!', ' ', '-'];
      final random = Random(25);
      for (var i = 0; i < 20000; i++) {
        final length = random.nextInt(15);
        final password = [
          for (var j = 0; j < length; j++)
            alphabet[random.nextInt(alphabet.length)],
        ].join();
        final listed =
            PasswordPolicy.unmet(password).isEmpty && !password.contains(' ');
        expect(PasswordPolicy.isValid(password), listed, reason: password);
        expect(
          PasswordPolicy.validate(password) == null,
          listed,
          reason: password,
        );
      }
    });

    test('ticks each off as it is met', () {
      expect(PasswordPolicy.unmet(''), hasLength(5));
      expect(
        PasswordPolicy.unmet('abc').map((rule) => rule.label),
        isNot(contains('One lowercase letter')),
      );
      expect(PasswordPolicy.unmet('Abcdefg1'), hasLength(1));
      expect(PasswordPolicy.unmet('Abcdefg1!'), isEmpty);
      // A space is not a special character.
      expect(
        PasswordPolicy.unmet('Abcdefg1 ').single.label,
        contains('special'),
      );
      expect(PasswordPolicy.validate(''), 'Choose a password.');
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
