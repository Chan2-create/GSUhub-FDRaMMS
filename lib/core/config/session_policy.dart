/// How long a sign-in lasts without the person doing anything, on the
/// console and on both phone apps alike: 15 minutes (Chris, 2026-11-15; it
/// was 30 from 2026-11-14), with a warning and a countdown for the last
/// two.
///
/// The database holds the same limit and is what enforces it
/// (`app.inactivity_limit()` in supabase/migrations/*_session_inactivity.sql);
/// `test/unit/core/inactivity_monitor_test.dart` keeps the two equal. The
/// apps' timers are for warning the person and signing out cleanly.
abstract final class SessionPolicy {
  /// Idle this long, and the session ends.
  static const Duration inactivityLimit = Duration(minutes: 15);

  /// How long before the end the warning shows: at 13 minutes.
  static const Duration warningBefore = Duration(minutes: 2);

  /// How often, at most, the app tells the database the person is active.
  static const Duration touchInterval = Duration(minutes: 1);

  /// What the sign-in page says after a session ended on its own.
  static const String endedMessage =
      'You were signed out after 15 minutes of inactivity. Sign in again to '
      'continue.';

  /// What the sign-in page says after an administrator deactivated the
  /// account (2026-11-17), in the brief's words.
  static const String deactivatedMessage =
      'Your account has been deactivated by the Administrator. You have been '
      'logged out. If you believe this action was made in error, please '
      "contact the GSU Administrator's Office.";

  /// What the sign-in page says after an administrator changed the
  /// account's role (2026-11-17), in the brief's words.
  static const String roleChangedMessage =
      'Your account role has been changed by the Administrator, and you have '
      'been logged out. If you did not request or expect this change, please '
      "visit the GSU Administrator's Office for clarification.";

  /// What the sign-in page says after a session ended for [reason].
  static String messageFor(SessionEndReason reason) => switch (reason) {
    SessionEndReason.idle => endedMessage,
    SessionEndReason.deactivated => deactivatedMessage,
    SessionEndReason.roleChanged => roleChangedMessage,
  };
}

/// Why a session ended without the person asking (2026-11-17). The
/// database says which, in the refusal's hint and from `session_state`
/// (supabase/migrations/*_account_sessions_and_departments.sql).
enum SessionEndReason {
  /// 15 minutes without activity.
  idle,

  /// An administrator deactivated the account.
  deactivated,

  /// An administrator changed the account's role.
  roleChanged;

  /// The reason the database names, or null for "active" or anything not
  /// known here.
  static SessionEndReason? fromDatabase(String? value) => switch (value) {
    'idle' => idle,
    'deactivated' => deactivated,
    'roleChanged' => roleChanged,
    _ => null,
  };
}
