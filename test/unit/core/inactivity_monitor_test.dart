import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/config/session_policy.dart';
import 'package:gsuhub/core/session/inactivity_monitor.dart';

/// The session's clock: 15 minutes without activity (2026-11-15; 30 before), a
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

  /// When the warning shows: 13 minutes in, two before the end.
  final warningAt = SessionPolicy.inactivityLimit - SessionPolicy.warningBefore;

  test('the policy: 15 minutes, warned at 13, as the database has it', () {
    expect(SessionPolicy.inactivityLimit, const Duration(minutes: 15));
    expect(
      SessionPolicy.inactivityLimit - SessionPolicy.warningBefore,
      const Duration(minutes: 13),
    );
    final migration = File(
      'supabase/migrations/20261115093218_session_inactivity_15_minutes.sql',
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
    expect(SessionPolicy.endedMessage, contains('15 minutes'));
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

  test('active for 13 minutes, warning for two, then expired', () {
    monitor.start();
    expect(monitor.isWatching, isTrue);
    expect(monitor.lastActivity, now);

    elapse(warningAt - const Duration(seconds: 1));
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
    elapse(const Duration(minutes: 10));
    monitor.touch();
    elapse(const Duration(minutes: 10));
    expect(
      monitor.phase,
      SessionPhase.active,
      reason: '10 minutes since the touch, not 20 since the start',
    );

    elapse(const Duration(minutes: 3));
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
    elapse(SessionPolicy.inactivityLimit + const Duration(minutes: 1));
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
    expect(monitor.endReason, SessionEndReason.idle);
  });

  test('and says why: the first reason given stands, until the next '
      'sign-in', () {
    monitor.start();
    monitor.expire(reason: SessionEndReason.deactivated);
    expect(monitor.phase, SessionPhase.expired);
    expect(monitor.endReason, SessionEndReason.deactivated);

    // A refusal arriving late on another call changes nothing.
    monitor.expire(reason: SessionEndReason.roleChanged);
    expect(monitor.endReason, SessionEndReason.deactivated);

    monitor
      ..stop()
      ..start();
    expect(monitor.endReason, SessionEndReason.idle);
  });

  test('each reason has its own words on the sign-in page', () {
    expect(
      SessionPolicy.messageFor(SessionEndReason.deactivated),
      'Your account has been deactivated by the Administrator. You have been '
      'logged out. If you believe this action was made in error, please '
      "contact the GSU Administrator's Office.",
    );
    expect(
      SessionPolicy.messageFor(SessionEndReason.roleChanged),
      'Your account role has been changed by the Administrator, and you have '
      'been logged out. If you did not request or expect this change, please '
      "visit the GSU Administrator's Office for clarification.",
    );
    expect(
      SessionPolicy.messageFor(SessionEndReason.idle),
      SessionPolicy.endedMessage,
    );
    // The database's refusals carry the same words.
    final migration =
        File(
              'supabase/migrations/20261117102846_account_sessions_and_departments.sql',
            )
            .readAsStringSync()
            .replaceAll("''", "'")
            .replaceAll(RegExp(r"'\s*\|\|\s*'"), '');
    expect(migration, contains(SessionPolicy.deactivatedMessage));
    expect(migration, contains(SessionPolicy.roleChangedMessage));
  });

  test('stopping forgets everything', () {
    monitor.start();
    elapse(warningAt + const Duration(minutes: 1));
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

    now = now.add(warningAt);
    expect(ticking.phase, SessionPhase.active, reason: 'not checked yet');
    await tester.pump(const Duration(seconds: 1));
    expect(ticking.phase, SessionPhase.warning);

    now = now.add(SessionPolicy.warningBefore);
    await tester.pump(const Duration(seconds: 1));
    expect(ticking.phase, SessionPhase.expired);

    ticking.stop();
    // No timer is left behind once stopped: the test would fail otherwise.
  });
}
