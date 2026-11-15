import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/notifications/presentation/push_coordinator.dart';
import '../config/session_policy.dart';
import '../di/repository_providers.dart';
import '../di/service_providers.dart';
import '../errors/failures.dart';
import '../routing/route_guards.dart';
import '../services/auth_service.dart';
import '../utils/result.dart';
import 'inactivity_monitor.dart';

/// Ends a sign-in that has gone unused (Chris, 2026-11-14), on the console
/// and on both phone apps: 15 minutes without the person doing anything,
/// a warning with a countdown for the last two, then signed out and back
/// on the sign-in page, which says why.
///
/// Two clocks agree on it. This one, through [InactivityMonitor], is for
/// warning and for signing out cleanly. The database's is the one that
/// counts: while the person is active the app tells it so through
/// `touch_session`, at most once a minute, and past the limit it refuses
/// every read and every change, whatever token the client holds
/// (supabase/migrations/*_session_inactivity.sql). A refusal (PT401)
/// reaching the app ends the session here too, through the monitor.
///
/// Activity is anything `SessionActivityListener` hears: pointer events,
/// mouse movement, scrolling, keys, and the page changing.
class SessionWatch {
  SessionWatch(this._ref, this._monitor);

  final Ref _ref;
  final InactivityMonitor _monitor;

  String Function()? _location;
  void Function(String location)? _go;
  DateTime? _lastTouch;
  bool _touching = false;
  bool _ending = false;

  /// The router's whereabouts and its `go`, handed over by the app: where
  /// the person was, and how to put them on the sign-in page.
  void attach({
    required String Function() location,
    required void Function(String location) go,
  }) {
    _location = location;
    _go = go;
  }

  /// Who is signed in, on every change. Watching begins with a sign-in
  /// and ends with any sign-out, including the one this class makes.
  void userChanged(AuthUser? user) {
    if (user == null) {
      _monitor.stop();
      _lastTouch = null;
      _ending = false;
      return;
    }
    _monitor.start();
    unawaited(_touchBackend());
  }

  /// The person did something.
  void activity() {
    if (!_monitor.isWatching) return;
    _monitor.touch();
    final last = _lastTouch;
    if (last == null ||
        _monitor.now().difference(last) >= SessionPolicy.touchInterval) {
      unawaited(_touchBackend());
    }
  }

  /// A phone app came back to the foreground: its timers may have slept
  /// with it, so the clock is read now.
  void resumed() => _monitor.check();

  /// What the monitor reports. Expiry ends the session, in a microtask so
  /// the monitor finishes notifying before it is stopped.
  void monitorChanged() {
    if (_monitor.phase == SessionPhase.expired) {
      scheduleMicrotask(_endExpired);
    }
  }

  /// "Sign out now" on the warning: a chosen Logout, with no notice.
  Future<void> signOutNow() => _end(expired: false);

  Future<void> _touchBackend() async {
    if (_touching || _ending) return;
    _touching = true;
    _lastTouch = _monitor.now();
    try {
      final result = await _ref.read(sessionRepositoryProvider).touch();
      if (result case Error(failure: SessionExpiredFailure())) {
        _monitor.expire();
      }
    } finally {
      _touching = false;
    }
  }

  Future<void> _endExpired() => _end(expired: true);

  Future<void> _end({required bool expired}) async {
    if (_ending) return;
    _ending = true;
    final location = _location?.call();
    _monitor.stop();
    // The phone's push token goes first, while the account can still clear
    // it, as the Profile page's Logout does. Nothing for the console.
    await _ref.read(pushCoordinatorProvider).signOutDevice();
    final auth = _ref.read(authControllerProvider.notifier);
    if (expired) {
      await auth.signOutExpired();
    } else {
      await auth.signOut();
    }
    if (location == null) return;
    // Signing in again returns to the page the session ended on; a chosen
    // Logout starts over at the sign-in page.
    _go?.call(
      expired
          ? AppRouteGuard.signedOutLocationFor(location)
          : AppRouteGuard.loginPageFor(location),
    );
  }
}

/// Lives as long as the app: watching whoever is signed in.
final sessionWatchProvider = Provider<SessionWatch>((ref) {
  final monitor = ref.watch(inactivityMonitorProvider);
  final watch = SessionWatch(ref, monitor);
  monitor.addListener(watch.monitorChanged);
  ref
    ..listen(
      authStateProvider,
      (_, next) => watch.userChanged(next.value),
      fireImmediately: true,
    )
    ..onDispose(() {
      monitor.removeListener(watch.monitorChanged);
      // The app is going; the clock it drove stops with it.
      monitor.stop();
    });
  return watch;
});
