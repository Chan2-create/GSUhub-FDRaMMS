import '../../errors/supabase_error_mapper.dart';
import '../call_guard.dart';

/// The [CallGuard] for Supabase calls: timeout, retry, and Postgrest,
/// Storage and token-exchange errors mapped by [SupabaseErrorMapper].
class SupabaseCallGuard extends CallGuard {
  const SupabaseCallGuard(super.config)
    : super(
        map: SupabaseErrorMapper.map,
        isRetryable: SupabaseErrorMapper.isRetryable,
      );
}
