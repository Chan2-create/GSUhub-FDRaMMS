import 'package:gsuhub/core/config/session_policy.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/auth/data/repositories/session_repository.dart';

/// The database's side of the session, in memory: counts the app's
/// touches, and answers what a test says (2026-11-14).
class FakeSessionRepository implements SessionRepository {
  /// What the next touch answers: by default, that the session is alive.
  Result<void> touchResult = const Result.success(null);

  /// How many times the app said the person was active.
  int touches = 0;

  @override
  Future<Result<void>> touch() async {
    touches++;
    return touchResult;
  }

  /// What the database says of the session when asked (2026-11-17): by
  /// default, that it is active.
  Result<SessionEndReason?> stateResult = const Result.success(null);

  /// How many times the app asked where the session stands.
  int stateChecks = 0;

  @override
  Future<Result<SessionEndReason?>> state() async {
    stateChecks++;
    return stateResult;
  }
}
