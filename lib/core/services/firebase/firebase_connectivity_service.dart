import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../constants/firestore_paths.dart';
import '../../errors/failures.dart';
import '../../utils/result.dart';
import '../connectivity_service.dart';
import 'firebase_call_guard.dart';

/// Firestore-backed [ConnectivityService].
///
/// Probes reachability by reading a document with
/// `GetOptions(source: Source.server)`, which bypasses the offline cache
/// and therefore fails when the server genuinely cannot be reached. A
/// normal read would be answered from cache and report "online" while
/// completely disconnected.
///
/// The probe target is `config/prioritization` — a document every signed-in
/// role is allowed to read (see `firestore.rules`), tiny, and one the app
/// needs anyway. Using a real document rather than a dedicated ping record
/// avoids a collection that exists only to be polled.
class FirebaseConnectivityService implements ConnectivityService {
  FirebaseConnectivityService({
    required this._firestore,
    required this._guard,
    this._pollInterval = const Duration(seconds: 30),
  });

  final FirebaseFirestore _firestore;
  final FirebaseCallGuard _guard;
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
      await _firestore
          .collection(FirestorePaths.config)
          .doc('prioritization')
          .get(const GetOptions(source: Source.server));
      return true;
    });

    return result.fold(
      (reachable) {
        _emit(BackendReachability.online);
        return Result.success(reachable);
      },
      (failure) {
        // A permission denial still proves the server answered, so it
        // counts as reachable. Only a transport failure means offline.
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

  /// Stops polling. Call when the service is no longer needed; the
  /// Riverpod provider wires this to its `onDispose`.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_controller.close());
  }
}
