import 'dart:async';

import 'package:supabase/supabase.dart';

import '../../errors/failures.dart';
import '../../utils/result.dart';
import '../connectivity_service.dart';
import 'supabase_call_guard.dart';

/// Supabase-backed [ConnectivityService].
///
/// Probes by reading one row of `app_config`: tiny, and readable by every
/// active account. Any answer from the server proves it is reachable,
/// including a refusal (signed out, or deactivated); only a failed
/// connection or a timeout counts as offline. There is no offline cache to
/// mislead it, unlike Firestore's.
class SupabaseConnectivityService implements ConnectivityService {
  SupabaseConnectivityService({
    required this._client,
    required this._guard,
    this._pollInterval = const Duration(seconds: 30),
  });

  final SupabaseClient _client;
  final SupabaseCallGuard _guard;
  final Duration _pollInterval;

  final StreamController<BackendReachability> _controller =
      StreamController<BackendReachability>.broadcast();

  Timer? _timer;
  BackendReachability _current = BackendReachability.unknown;

  @override
  BackendReachability get current => _current;

  @override
  Stream<BackendReachability> get reachability {
    _ensurePolling();
    return _controller.stream;
  }

  @override
  Future<Result<bool>> checkReachable() async {
    final result = await _guard.call(() async {
      await _client.from('app_config').select('id').limit(1);
      return true;
    });

    return result.fold(
      (reachable) {
        _emit(BackendReachability.online);
        return Result.success(reachable);
      },
      (failure) {
        _emit(
          failure is NetworkFailure
              ? BackendReachability.offline
              : BackendReachability.online,
        );
        return Result.failure(failure);
      },
    );
  }

  void _ensurePolling() {
    _timer ??= Timer.periodic(_pollInterval, (_) => unawaited(_probe()));
    unawaited(_probe());
  }

  Future<void> _probe() async {
    if (_controller.isClosed) return;
    await checkReachable();
  }

  void _emit(BackendReachability value) {
    _current = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  /// Stops polling; the provider wires this to its `onDispose`.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_controller.close());
  }
}
