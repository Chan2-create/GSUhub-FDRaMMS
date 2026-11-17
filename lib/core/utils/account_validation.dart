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

/// What a new password must be (2026-11-17): the one place the rules are
/// written, for the requirements shown under the field and the check
/// before the account is created.
///
/// The password goes to Firebase Authentication and never reaches the
/// database, so the server's side of this check is Firebase's own
/// password policy, which is set to the same rules in the Firebase
/// console (docs/manual_deploy.md). A password typed to sign in is not
/// held to these: accounts made before them keep their passwords.
abstract final class PasswordPolicy {
  static const int minLength = 8;

  static final List<PasswordRule> rules = [
    PasswordRule(
      'At least $minLength characters',
      (password) => password.length >= minLength,
    ),
    PasswordRule(
      'An uppercase letter (A–Z)',
      (password) => password.contains(RegExp('[A-Z]')),
    ),
    PasswordRule(
      'A lowercase letter (a–z)',
      (password) => password.contains(RegExp('[a-z]')),
    ),
    PasswordRule(
      'A number (0–9)',
      (password) => password.contains(RegExp('[0-9]')),
    ),
    PasswordRule(
      r'A special character, such as ! @ # $ %',
      (password) => password.contains(RegExp(r'[^A-Za-z0-9\s]')),
    ),
  ];

  /// The rules [password] does not meet yet, in the order they are listed.
  static List<PasswordRule> unmet(String password) => [
    for (final rule in rules)
      if (!rule.isMetBy(password)) rule,
  ];

  /// What is wrong with [password] as a new password, or null.
  static String? validate(String password) {
    if (password.isEmpty) return 'Choose a password.';
    final missing = unmet(password);
    if (missing.isEmpty) return null;
    return 'Your password still needs: '
        '${missing.map((rule) => _lower(rule.label)).join(', ')}.';
  }

  static String _lower(String label) =>
      label[0].toLowerCase() + label.substring(1);
}
