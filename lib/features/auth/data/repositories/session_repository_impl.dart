import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import 'session_repository.dart';

/// Supabase-backed [SessionRepository]: `touch_session`, which writes the
/// caller's row of `app.user_activity` (not exposed) as of now.
class SessionRepositoryImpl extends SupabaseRepository
    implements SessionRepository {
  const SessionRepositoryImpl({required super.client, required super.guard});

  @override
  Future<Result<void>> touch() => rpc('touch_session', const {});
}
