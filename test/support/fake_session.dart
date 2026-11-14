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
}
