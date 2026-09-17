import '../utils/result.dart';

/// Whether the backend is currently reachable.
enum BackendReachability {
  /// Reads and writes are reaching the server.
  online,

  /// The client is running, but requests are not reaching Firebase —
  /// no network, or the backend is unreachable.
  offline,

  /// Not yet determined.
  unknown,
}

/// Reports whether GSUhub can currently reach its backend.
///
/// Manuscript §1.5 lists internet connectivity as a hard requirement:
/// "Internet connectivity is required for timely database access, data
/// synchronization, image uploads, notifications, and communication
/// between the mobile applications and the web-based administrative
/// system."
///
/// That makes reachability a first-class state the UI must be able to
/// show, not an error to discover one failed request at a time. Firestore
/// compounds this: its offline cache will happily serve stale reads and
/// queue writes indefinitely without surfacing anything, so a user can
/// work for several minutes against data that is silently out of date.
abstract interface class ConnectivityService {
  /// Current reachability, updated as it changes.
  Stream<BackendReachability> get reachability;

  /// Last known reachability, for synchronous checks.
  BackendReachability get current;

  /// Actively probes the backend rather than reporting a cached verdict.
  Future<Result<bool>> checkReachable();
}
