import '../../../../core/config/session_policy.dart';
import '../../../../core/utils/result.dart';

/// The database's side of a sign-in's session (2026-11-14): that the
/// person is still using the app. The database ends a session idle for 30
/// minutes (supabase/migrations/*_session_inactivity.sql); this is how it
/// knows one is not idle.
abstract interface class SessionRepository {
  /// Records that the signed-in person is active now. Fails with
  /// `SessionExpiredFailure` when the database has already ended the
  /// session: touching late revives nothing.
  Future<Result<void>> touch();

  /// Where the session stands, without counting as activity
  /// (2026-11-17): null while it is active, or why the database ended it.
  /// Asked whenever the signed-in person's own account changes, so an
  /// administrator deactivating it or changing its role signs them out.
  Future<Result<SessionEndReason?>> state();
}
