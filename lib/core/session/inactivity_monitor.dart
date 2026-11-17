import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/session_policy.dart';

/// Where a session stands against the inactivity limit.
enum SessionPhase {
  /// In use, or idle for less than the warning allows.
  active,

  /// Idle long enough that the end is near: the apps show the countdown.
  warning,

  /// Idle past the limit, or ended by the database: the apps sign out.
  expired,
}

/// Keeps the time since the person last did anything, and says when the
/// session should warn and when it should end (2026-11-14). One clock for
/// the console and both phone apps.
///
/// Measured against the wall clock, not by counting ticks: a laptop closed
/// for an hour, or a phone app left in the background, comes back to a
/// session that has ended, not to one with an hour of ticks still to run.
/// [check] runs every second while watching, and again when a phone app
/// returns to the foreground.
///
/// Knows nothing of signing in or out: `SessionWatch` starts and stops it
/// and acts on what it reports.
class InactivityMonitor extends ChangeNotifier {
  InactivityMonitor({
    DateTime Function()? clock,
    this.limit = SessionPolicy.inactivityLimit,
    this.warningBefore = SessionPolicy.warningBefore,
    this.tick = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now;

  /// Idle this long, and the session has ended.
  final Duration limit;

  /// The warning shows when this much is left.
  final Duration warningBefore;

  /// How often the clock is checked while watching.
  final Duration tick;

  final DateTime Function() _clock;

  DateTime? _lastActivity;
  Timer? _ticker;
  SessionPhase _phase = SessionPhase.active;

  /// The time, by the clock this monitor keeps; a test's clock in tests.
  DateTime now() => _clock();

  /// Whether a session is being watched: between [start] and [stop].
  bool get isWatching => _lastActivity != null;

  SessionPhase get phase => _phase;

  /// When the person last did anything, while watching.
  DateTime? get lastActivity => _lastActivity;

  /// How long the session has left; zero once it has ended.
  Duration get remaining {
    final last = _lastActivity;
    if (last == null) return limit;
    final left = limit - _clock().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  /// Starts watching, counting from now. Signing in.
  void start() {
    _lastActivity = _clock();
    _endReason = SessionEndReason.idle;
    _ticker ??= Timer.periodic(tick, (_) => check());
    _setPhase(SessionPhase.active);
  }

  /// Stops watching. Signing out, however it happened.
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _lastActivity = null;
    _setPhase(SessionPhase.active);
  }

  /// The person did something: the count starts over, and a warning that
  /// was showing goes away. Cheap: it is called for every pointer event.
  void touch() {
    if (_lastActivity == null || _phase == SessionPhase.expired) return;
    _lastActivity = _clock();
    if (_phase == SessionPhase.warning) _setPhase(SessionPhase.active);
  }

  /// Compares the clock with the last activity, and moves the phase on.
  /// During the warning, every call notifies, so a countdown can follow it.
  void check() {
    if (_lastActivity == null || _phase == SessionPhase.expired) return;
    final left = remaining;
    if (left == Duration.zero) {
      _setPhase(SessionPhase.expired);
    } else if (left <= warningBefore) {
      if (_phase == SessionPhase.warning) {
        notifyListeners();
      } else {
        _setPhase(SessionPhase.warning);
      }
    }
  }

  /// Why the session ended, once [phase] is expired: idle when the time
  /// ran out here.
  SessionEndReason get endReason => _endReason;
  SessionEndReason _endReason = SessionEndReason.idle;

  /// The session ended elsewhere: the database refused it, as idle, or
  /// (2026-11-17) because an administrator deactivated the account or
  /// changed its role. Idle is the same as the time running out here.
  void expire({SessionEndReason reason = SessionEndReason.idle}) {
    if (_lastActivity == null) return;
    // The first reason given stands: a refusal arriving late on another
    // call does not change what the person is told.
    if (_phase != SessionPhase.expired) _endReason = reason;
    _setPhase(SessionPhase.expired);
  }

  void _setPhase(SessionPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}

/// The app's one monitor. Tests give it a clock they control.
final inactivityMonitorProvider = Provider<InactivityMonitor>((ref) {
  final monitor = InactivityMonitor();
  ref.onDispose(monitor.dispose);
  return monitor;
});
