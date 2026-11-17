import '../../../../core/config/session_policy.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import 'session_repository.dart';

/// Supabase-backed [SessionRepository]: `touch_session`, which writes the
/// caller's row of `app.user_activity` (not exposed) as of now.
class SessionRepositoryImpl extends SupabaseRepository
    implements SessionRepository {
  const SessionRepositoryImpl({
    required super.client,
    required super.guard,
    super.live,
  });

  @override
  Future<Result<void>> touch() =>
      // Changes nothing a screen shows: no reason to read them all again.
      rpc('touch_session', const {}, changesData: false);

  @override
  Future<Result<SessionEndReason?>> state() async => (await rpcFor<String>(
    'session_state',
    const {},
    changesData: false,
  )).map(SessionEndReason.fromDatabase);
}
