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
}
