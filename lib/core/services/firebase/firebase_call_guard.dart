import '../call_guard.dart';
import 'firebase_error_mapper.dart';

/// The [CallGuard] for Firebase calls: timeout, retry, and Firebase's
/// string-coded errors mapped by [FirebaseErrorMapper].
///
/// Deterministic failures (permission denied, not found, validation)
/// return immediately — see [FirebaseErrorMapper.isRetryable].
class FirebaseCallGuard extends CallGuard {
  const FirebaseCallGuard(super.config)
    : super(
        map: FirebaseErrorMapper.map,
        isRetryable: FirebaseErrorMapper.isRetryable,
      );
}
