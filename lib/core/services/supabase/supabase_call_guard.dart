import '../../errors/supabase_error_mapper.dart';
import '../call_guard.dart';

/// The [CallGuard] for Supabase calls: timeout, retry, and Postgrest,
/// Storage and token-exchange errors mapped by [SupabaseErrorMapper].
///
/// [onFailure] hears every mapped failure: the app uses it to notice a
/// session the database has ended (`SessionExpiredFailure`), whichever
/// call it surfaced on.
class SupabaseCallGuard extends CallGuard {
  const SupabaseCallGuard(super.config, {super.onFailure})
    : super(
        map: SupabaseErrorMapper.map,
        isRetryable: SupabaseErrorMapper.isRetryable,
      );
}
