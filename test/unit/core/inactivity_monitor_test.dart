import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/config/session_policy.dart';
import 'package:gsuhub/core/session/inactivity_monitor.dart';

/// The session's clock (2026-11-14): 30 minutes without activity, a
/// warning for the last two, measured against the wall clock.
void main() {
  late DateTime now;
  late InactivityMonitor monitor;
  late int notifications;

  setUp(() {
    now = DateTime(2026, 11, 14, 9);
    notifications = 0;
    // A tick an hour long: these tests call check() themselves.
    monitor = InactivityMonitor(
      clock: () => now,
      tick: const Duration(hours: 1),
    )..addListener(() => notifications++);
  });

  tearDown(() => monitor.dispose());

  void elapse(Duration duration) {
    now = now.add(duration);
    monitor.check();
  }

  test('the policy: 30 minutes, warned at 28, as the database has it', () {
    expect(SessionPolicy.inactivityLimit, const Duration(minutes: 30));
    expect(
      SessionPolicy.inactivityLimit - SessionPolicy.warningBefore,
      const Duration(minutes: 28),
    );
    final migration = File(
      'supabase/migrations/20261114140451_session_inactivity.sql',
    ).readAsStringSync();
    expect(
      migration,
      contains("interval '${SessionPolicy.inactivityLimit.inMinutes} minutes'"),
      reason: 'the database enforces the same limit the app warns about',
    );
    expect(
      migration,
      contains(
        'after ${SessionPolicy.inactivityLimit.inMinutes} minutes of '
        'inactivity',
      ),
      reason: 'and says the same number in its refusal',
    );
    expect(SessionPolicy.endedMessage, contains('30 minutes'));
  });

  test('not watching until started, and idle for nothing then', () {
    expect(monitor.isWatching, isFalse);
    expect(monitor.phase, SessionPhase.active);
    expect(monitor.remaining, SessionPolicy.inactivityLimit);
    monitor.check();
    monitor.touch();
    monitor.expire();
    expect(monitor.phase, SessionPhase.active);
    expect(notifications, 0);
  });

  test('active for 28 minutes, warning for two, then expired', () {
    monitor.start();
    expect(monitor.isWatching, isTrue);
    expect(monitor.lastActivity, now);

    elapse(const Duration(minutes: 27, seconds: 59));
    expect(monitor.phase, SessionPhase.active);
    expect(notifications, 0, reason: 'nothing to show yet');

    elapse(const Duration(seconds: 1));
    expect(monitor.phase, SessionPhase.warning);
    expect(monitor.remaining, const Duration(minutes: 2));
    expect(notifications, 1);

    elapse(const Duration(seconds: 1));
    expect(monitor.remaining, const Duration(minutes: 1, seconds: 59));
    expect(notifications, 2, reason: 'every check in the warning counts down');

    elapse(const Duration(minutes: 1, seconds: 59));
    expect(monitor.phase, SessionPhase.expired);
    expect(monitor.remaining, Duration.zero);
  });

  test('doing something starts the count over and clears the warning', () {
    monitor.start();
    elapse(const Duration(minutes: 20));
    monitor.touch();
    elapse(const Duration(minutes: 20));
    expect(
      monitor.phase,
      SessionPhase.active,
      reason: '20 minutes since the touch, not 40 since the start',
    );

    elapse(const Duration(minutes: 9));
    expect(monitor.phase, SessionPhase.warning);
    monitor.touch();
    expect(monitor.phase, SessionPhase.active);
    expect(monitor.remaining, SessionPolicy.inactivityLimit);
  });

  test('a long sleep goes straight to expired: the wall clock decides', () {
    monitor.start();
    now = now.add(const Duration(hours: 3));
    monitor.check();
    expect(monitor.phase, SessionPhase.expired);
    expect(notifications, 1, reason: 'no warning first');
  });

  test('once expired, nothing short of starting again revives it', () {
    monitor.start();
    elapse(const Duration(minutes: 31));
    monitor.touch();
    expect(monitor.phase, SessionPhase.expired);
    monitor.check();
    expect(monitor.phase, SessionPhase.expired);

    monitor.start();
    expect(monitor.phase, SessionPhase.active);
    expect(monitor.remaining, SessionPolicy.inactivityLimit);
  });

  test('the database can end it too', () {
    monitor.start();
    elapse(const Duration(minutes: 5));
    monitor.expire();
    expect(monitor.phase, SessionPhase.expired);
  });

  test('stopping forgets everything', () {
    monitor.start();
    elapse(const Duration(minutes: 29));
    expect(monitor.phase, SessionPhase.warning);
    monitor.stop();
    expect(monitor.isWatching, isFalse);
    expect(monitor.phase, SessionPhase.active);
    expect(monitor.lastActivity, isNull);
    elapse(const Duration(hours: 1));
    expect(monitor.phase, SessionPhase.active);
  });

  testWidgets('while watching, it checks the clock every second', (
    tester,
  ) async {
    final ticking = InactivityMonitor(clock: () => now);
    addTearDown(ticking.dispose);
    ticking.start();

    now = now.add(const Duration(minutes: 28));
    expect(ticking.phase, SessionPhase.active, reason: 'not checked yet');
    await tester.pump(const Duration(seconds: 1));
    expect(ticking.phase, SessionPhase.warning);

    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(ticking.phase, SessionPhase.expired);

    ticking.stop();
    // No timer is left behind once stopped: the test would fail otherwise.
  });
}
