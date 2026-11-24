/// The checks an account's details go through before they are sent
/// (2026-11-17). The database makes the same ones and has the last word
/// (supabase/migrations/*_account_sessions_and_departments.sql); these
/// say what is wrong beside the field, before a round trip.
///
/// GSUhub signs in with an email address: there is no username to check.
abstract final class AccountValidation {
  /// An email's shape: something, an @, something, a dot, something. The
  /// sign-in service is the real judge of an address; the database checks
  /// the same pattern.
  static final RegExp emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// A Philippine mobile number: 09 and nine digits, or +639 and nine,
  /// once spaces and dashes are taken out.
  static final RegExp mobilePattern = RegExp(r'^(09|\+639)\d{9}$');

  /// [value] without the spaces and dashes people type in a number.
  static String compactNumber(String value) =>
      value.replaceAll(RegExp(r'[\s-]'), '');

  /// What is wrong with an optional mobile number, or null.
  static String? contactNumber(String? value) {
    final number = compactNumber(value ?? '');
    if (number.isEmpty) return null;
    if (!mobilePattern.hasMatch(number)) {
      return 'Enter a Philippine mobile number: 11 digits starting with 09, '
          'or +63 followed by 9.';
    }
    return null;
  }

  /// What is wrong with a required email address, or null. [missing] is
  /// what to say when there is none.
  static String? email(
    String? value, {
    String missing = 'Enter your email address.',
  }) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return missing;
    if (email.length > 254 || !emailPattern.hasMatch(email)) {
      return 'Enter a valid email address, such as juan.dc@dorsu.edu.ph.';
    }
    return null;
  }
}

/// One condition a new password must meet.
class PasswordRule {
  const PasswordRule(this.label, this._test);

  /// As the requirements list under the field says it.
  final String label;

  final bool Function(String password) _test;

  bool isMetBy(String password) => _test(password);
}

/// What a new password must be: the one place the rules are written, for
/// the requirements shown under the field, the check before the account
/// is created, and the console's starter passwords.
///
/// **2026-11-25:** 8 to 12 characters, no spaces, and the special
/// character one of Firebase's own (below), as one regular expression,
/// [pattern]. The five [rules] are that expression taken apart for the
/// list under the field; `test/unit/core/account_validation_test.dart`
/// checks the two agree.
///
/// The password goes to Firebase Authentication and never reaches the
/// database, so the server's side of this check is Firebase's own
/// password policy, set to the same rules in the Firebase console
/// (docs/manual_deploy.md); Firebase stores only a hash of it. A password
/// typed to sign in is not held to these: accounts made before them keep
/// their passwords.
abstract final class PasswordPolicy {
  static const int minLength = 8;
  static const int maxLength = 12;

  /// The characters Firebase's password policy counts as non-alphanumeric
  /// (firebase.google.com/docs/auth/web/password-auth, "Password policy").
  /// Others, such as `-` or `+`, may be in a password but do not meet the
  /// rule, since Firebase would not count them. The backtick is left out:
  /// Google's two pages disagree on it.
  static const String specialCharacters =
      r'^$*.[]{}()?"!@#%&/\,><'
      "'"
      r':;|_~';

  /// [specialCharacters] as a character class, escaped by hand.
  static const String _specialClass =
      r'[\^$*.\[\]{}()?"!@#%&/\\,><'
      "'"
      r':;|_~]';

  /// The whole policy: an uppercase letter, a lowercase letter, a digit
  /// and a special character somewhere, and 8 to 12 characters of which
  /// none is a space. Written out, it reads
  /// `^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[special])\S{8,12}$`.
  static final RegExp pattern = RegExp(
    r'^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*' +
        _specialClass +
        r')\S{' +
        '$minLength,$maxLength' +
        r'}$',
  );

  static final RegExp _special = RegExp(_specialClass);
  static final RegExp _space = RegExp(r'\s');

  static final List<PasswordRule> rules = [
    PasswordRule(
      '$minLength–$maxLength characters',
      (password) =>
          password.length >= minLength && password.length <= maxLength,
    ),
    PasswordRule(
      'One uppercase letter',
      (password) => password.contains(RegExp('[A-Z]')),
    ),
    PasswordRule(
      'One lowercase letter',
      (password) => password.contains(RegExp('[a-z]')),
    ),
    PasswordRule(
      'One number',
      (password) => password.contains(RegExp('[0-9]')),
    ),
    PasswordRule(
      r'One special character (e.g., @ # $ ! % &)',
      (password) => password.contains(_special),
    ),
  ];

  /// Whether [password] meets the whole policy.
  static bool isValid(String password) => pattern.hasMatch(password);

  /// The rules [password] does not meet yet, in the order they are listed.
  static List<PasswordRule> unmet(String password) => [
    for (final rule in rules)
      if (!rule.isMetBy(password)) rule,
  ];

  /// What is wrong with [password] as a new password, or null.
  static String? validate(String password) {
    if (password.isEmpty) return 'Choose a password.';
    if (password.contains(_space)) return 'A password cannot contain spaces.';
    if (password.length > maxLength) {
      return 'Use no more than $maxLength characters.';
    }
    final missing = unmet(password);
    if (missing.isNotEmpty) {
      return 'Your password still needs: '
          '${missing.map((rule) => _lower(rule.label)).join(', ')}.';
    }
    // The list and the expression agree (the unit test holds them to it);
    // the expression has the last word.
    return isValid(password) ? null : 'Choose a different password.';
  }

  static String _lower(String label) =>
      label[0].toLowerCase() + label.substring(1);
}
