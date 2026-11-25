import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/data/live_sync.dart';

/// A passing failure: the connection, a timeout.
class _Blip implements Exception {
  @override
  String toString() => 'blip';
}

/// A lasting one: a refusal.
class _Refusal implements Exception {
  @override
  String toString() => 'refused';
}

class _Channel implements ChangeChannel {
  _Channel(this.onChange, this.onStatus);

  final void Function(String table) onChange;
  final void Function(ChangeChannelStatus status) onStatus;
  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}

/// A table, the channel that would announce its changes, and whoever is
/// signed in: everything [LiveSync] talks to.
class _Backend {
  final channels = <_Channel>[];
  bool signedIn = true;

  List<Map<String, dynamic>> rows = [
    {'id': 'r-1', 'status': 'submitted'},
  ];
  int reads = 0;
  Object? failure;

  /// Held reads, when a test wants to answer them itself.
  final held = <Completer<void>>[];
  bool holdReads = false;

  late final LiveSync sync = LiveSync(
    openChannel: ({required onChange, required onStatus}) {
      final channel = _Channel(onChange, onStatus);
      channels.add(channel);
      return channel;
    },
    isSignedIn: () => signedIn,
    isTransient: (error) => error is _Blip,
  );

  _Channel get channel => channels.last;

  Future<LiveRows> fetch() async {
    reads++;
    if (holdReads) {
      final gate = Completer<void>();
      held.add(gate);
      await gate.future;
    }
    final failed = failure;
    if (failed != null) throw failed;
    return [
      for (final row in rows) {...row},
    ];
  }

  Stream<LiveRows> watch([String table = 'damage_reports']) =>
      sync.watchRows(tables: {table}, fetch: fetch);

  void setStatus(String status) => rows = [
    {'id': 'r-1', 'status': status},
  ];
}

/// What a screen would have seen: the rows and the errors, in order.
class _Screen {
  _Screen(Stream<LiveRows> stream) {
    subscription = stream.listen(
      (rows) => seen.add(rows.map((row) => row['status']).join(',')),
      onError: (Object error) => seen.add('error: $error'),
    );
  }

  // Let go with the LiveSync it listens to, at the end of each test.
  // ignore: cancel_subscriptions
  late final StreamSubscription<LiveRows> subscription;
  final seen = <String>[];
}

void main() {
  /// Runs [body] under the test's clock, and lets go of everything after.
  void liveTest(
    String name,
    Future<void> Function(WidgetTester tester, _Backend backend) body,
  ) => testWidgets(name, (tester) async {
    final backend = _Backend();
    try {
      await body(tester, backend);
    } finally {
      backend.sync.dispose();
    }
  });

  group('a live view', () {
    liveTest('reads when first watched, over one channel for them all', (
      tester,
      backend,
    ) async {
      final reports = _Screen(backend.watch());
      final tools = _Screen(backend.watch('tools'));
      await tester.pump();

      expect(reports.seen, ['submitted']);
      expect(tools.seen, ['submitted']);
      expect(backend.channels, hasLength(1));
      expect(backend.sync.watchedQueries, 2);
    });

    liveTest('is read again when a row of its table changes', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();
      backend.channel.onStatus(ChangeChannelStatus.subscribed);
      await tester.pump();
      final before = backend.reads;

      backend.setStatus('underReview');
      // A burst of changes to the table is one read.
      backend.channel
        ..onChange('damage_reports')
        ..onChange('damage_reports')
        ..onChange('damage_reports');
      await tester.pump(backend.sync.changeDebounce);
      await tester.pump();

      expect(screen.seen, ['submitted', 'underReview']);
      expect(backend.reads, before + 1);
    });

    liveTest('ignores a change to a table it does not show', (
      tester,
      backend,
    ) async {
      _Screen(backend.watch());
      await tester.pump();
      final before = backend.reads;

      backend.channel.onChange('tools');
      await tester.pump(backend.sync.changeDebounce);
      await tester.pump();

      expect(backend.reads, before);
    });

    liveTest('emits nothing when the rows read are the rows shown', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();

      await backend.sync.resync();
      await tester.pump();

      expect(backend.reads, 2);
      expect(screen.seen, ['submitted']);
    });
  });

  group('after a save', () {
    liveTest(
      'the screen has the saved rows before the save reports its result, '
      'with no change announced at all',
      (tester, backend) async {
        final screen = _Screen(backend.watch());
        await tester.pump();
        // The channel never joined, and never says a word.

        backend.setStatus('approved');
        var answered = false;
        unawaited(backend.sync.changed().then((_) => answered = true));
        await tester.pump();

        expect(answered, isTrue);
        expect(screen.seen, ['submitted', 'approved']);
      },
    );

    liveTest('a read already under way is followed by another', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();

      // A read starts, and is answered with what the database held then.
      backend.holdReads = true;
      unawaited(backend.sync.resync());
      await tester.pump();
      expect(backend.held, hasLength(1));

      // The save lands while it is in flight.
      backend.setStatus('approved');
      var answered = false;
      unawaited(backend.sync.changed().then((_) => answered = true));
      await tester.pump();
      expect(answered, isFalse, reason: 'the read in flight may be older');

      backend.holdReads = false;
      backend.held.single.complete();
      await tester.pump();
      await tester.pump();

      expect(answered, isTrue);
      expect(screen.seen.last, 'approved');
    });

    liveTest('a save that never reached the database waits for nothing', (
      tester,
      backend,
    ) async {
      _Screen(backend.watch());
      await tester.pump();
      backend.holdReads = true;

      var answered = false;
      unawaited(
        backend.sync.changed(reached: false).then((_) => answered = true),
      );
      await tester.pump();

      expect(answered, isTrue);
      expect(backend.held, hasLength(1), reason: 'read again all the same');
      backend.held.single.complete();
    });

    liveTest('gives up waiting on a read that does not answer', (
      tester,
      backend,
    ) async {
      _Screen(backend.watch());
      await tester.pump();
      backend.holdReads = true;

      var answered = false;
      unawaited(backend.sync.changed().then((_) => answered = true));
      await tester.pump(backend.sync.settleTimeout);
      await tester.pump();

      expect(answered, isTrue);
      backend.held.single.complete();
    });
  });

  group('signing out and in again', () {
    liveTest('the views are read again for the new sign-in, and are live '
        'again', (tester, backend) async {
      final screen = _Screen(backend.watch());
      await tester.pump();
      backend.channel.onStatus(ChangeChannelStatus.subscribed);
      await tester.pump();

      // Signed out: the client closes every channel.
      backend.signedIn = false;
      final first = backend.channel..onStatus(ChangeChannelStatus.closed);
      backend.sync.sessionChanged();
      await tester.pump(const Duration(minutes: 5));
      final readsSignedOut = backend.reads;
      expect(first.closed, isTrue);
      expect(backend.channels, hasLength(1), reason: 'no channel for nobody');
      expect(backend.sync.isLive, isFalse);

      // Something changes meanwhile, and they sign back in.
      backend
        ..setStatus('underReview')
        ..signedIn = true;
      backend.sync.sessionChanged();
      await tester.pump();

      expect(backend.reads, greaterThan(readsSignedOut));
      expect(screen.seen.last, 'underReview');
      expect(backend.channels, hasLength(2));

      // And changes are heard again.
      backend.channel.onStatus(ChangeChannelStatus.subscribed);
      await tester.pump();
      backend.setStatus('approved');
      backend.channel.onChange('damage_reports');
      await tester.pump(backend.sync.changeDebounce);
      await tester.pump();

      expect(screen.seen.last, 'approved');
    });

    liveTest('nothing is read, or shown as an error, while signed out', (
      tester,
      backend,
    ) async {
      backend.signedIn = false;
      final screen = _Screen(backend.watch());
      await tester.pump();
      await backend.sync.resync();
      await tester.pump(const Duration(minutes: 1));

      expect(backend.reads, 0);
      expect(backend.channels, isEmpty);
      expect(screen.seen, isEmpty);
    });

    liveTest('a read refused because they signed out mid-way is not shown', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();

      backend.holdReads = true;
      unawaited(backend.sync.resync());
      await tester.pump();
      backend
        ..signedIn = false
        ..failure = _Refusal();
      backend.held.single.complete();
      await tester.pump();

      expect(screen.seen, ['submitted']);
    });
  });

  group('the channel', () {
    liveTest('is replaced when interrupted, and everything read again once '
        'the new one has joined', (tester, backend) async {
      final screen = _Screen(backend.watch());
      await tester.pump();
      final first = backend.channel..onStatus(ChangeChannelStatus.subscribed);
      await tester.pump();

      first.onStatus(ChangeChannelStatus.interrupted);
      expect(first.closed, isTrue);
      expect(backend.sync.isLive, isFalse);

      // A change made while it was down is announced by nobody.
      backend.setStatus('underReview');
      await tester.pump(backend.sync.retryDelay);
      expect(backend.channels, hasLength(2));
      backend.channel.onStatus(ChangeChannelStatus.subscribed);
      await tester.pump();

      expect(screen.seen, ['submitted', 'underReview']);
      expect(backend.sync.isLive, isTrue);
    });

    liveTest('having joined, everything is read once more a little later: '
        'the server answers a join before its change stream is running', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();
      backend.channel.onStatus(ChangeChannelStatus.subscribed);
      await tester.pump();

      // Changed in those first moments, and announced by nobody.
      backend.setStatus('underReview');
      await tester.pump(backend.sync.joinRecheck);
      await tester.pump();
      expect(screen.seen, ['submitted', 'underReview']);

      // Once, not on a timer.
      final reads = backend.reads;
      await tester.pump(backend.sync.joinRecheck * 4);
      expect(backend.reads, reads);
    });

    liveTest('is replaced when the server closes it', (tester, backend) async {
      _Screen(backend.watch());
      await tester.pump();
      backend.channel
        ..onStatus(ChangeChannelStatus.subscribed)
        ..onStatus(ChangeChannelStatus.closed);

      await tester.pump(backend.sync.retryDelay);

      expect(backend.channels, hasLength(2));
    });

    liveTest('that keeps failing is retried at a growing interval, never '
        'given up on', (tester, backend) async {
      _Screen(backend.watch());
      await tester.pump();

      for (var attempt = 0; attempt < 8; attempt++) {
        backend.channel.onStatus(ChangeChannelStatus.interrupted);
        await tester.pump(backend.sync.maxRetryDelay);
      }

      expect(backend.channels, hasLength(9));
    });

    liveTest('being down, the views are read on a timer instead', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();
      // Never joins.
      backend.setStatus('assigned');
      await tester.pump(backend.sync.pollInterval);
      await tester.pump();

      expect(screen.seen, ['submitted', 'assigned']);

      // Joined: the timer stops, after the one look back a join is owed.
      backend.channel.onStatus(ChangeChannelStatus.subscribed);
      await tester.pump(backend.sync.joinRecheck);
      await tester.pump();
      final reads = backend.reads;
      await tester.pump(backend.sync.pollInterval * 3);

      expect(backend.reads, reads);
    });

    liveTest('an old channel talking after it was replaced is not heard', (
      tester,
      backend,
    ) async {
      _Screen(backend.watch());
      await tester.pump();
      final old = backend.channel..onStatus(ChangeChannelStatus.interrupted);
      await tester.pump(backend.sync.retryDelay);
      backend.channel.onStatus(ChangeChannelStatus.subscribed);
      await tester.pump(backend.sync.joinRecheck);
      await tester.pump();
      final reads = backend.reads;

      old
        ..onStatus(ChangeChannelStatus.closed)
        ..onChange('damage_reports');
      await tester.pump(backend.sync.pollInterval);

      expect(backend.channels, hasLength(2));
      expect(backend.reads, reads);
      expect(backend.sync.isLive, isTrue);
    });

    liveTest('is let go a little after the last view is', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();
      final channel = backend.channel;

      // Not awaited: under the test's clock a cancel's own future does
      // not complete.
      unawaited(screen.subscription.cancel());
      await tester.pump();
      expect(backend.sync.watchedQueries, 0);
      expect(channel.closed, isFalse, reason: 'a page may be about to watch');

      await tester.pump(backend.sync.idleLinger);
      expect(channel.closed, isTrue);
    });

    liveTest('is kept when a page replaces its views all at once', (
      tester,
      backend,
    ) async {
      final before = _Screen(backend.watch());
      await tester.pump();
      backend.channel.onStatus(ChangeChannelStatus.subscribed);
      await tester.pump();

      unawaited(before.subscription.cancel());
      final after = _Screen(backend.watch('tools'));
      await tester.pump(backend.sync.idleLinger * 2);

      expect(backend.channels, hasLength(1));
      expect(backend.channel.closed, isFalse);
      expect(backend.sync.isLive, isTrue);
      expect(after.seen, ['submitted']);
    });
  });

  group('a read that fails', () {
    liveTest('for a passing reason keeps the rows on screen, and is tried '
        'again until it works', (tester, backend) async {
      final screen = _Screen(backend.watch());
      await tester.pump();

      backend
        ..failure = _Blip()
        ..setStatus('approved');
      await backend.sync.resync();
      await tester.pump();
      expect(screen.seen, ['submitted'], reason: 'no error over good rows');

      await tester.pump(backend.sync.retryDelay);
      await tester.pump();
      expect(screen.seen, ['submitted'], reason: 'still failing');

      backend.failure = null;
      await tester.pump(backend.sync.retryDelay * 2);
      await tester.pump();
      expect(screen.seen, ['submitted', 'approved']);
    });

    liveTest('with nothing on screen yet is shown, then replaced by the '
        'rows when a later try works', (tester, backend) async {
      backend.failure = _Blip();
      final screen = _Screen(backend.watch());
      await tester.pump();
      expect(screen.seen, ['error: blip']);

      await tester.pump(backend.sync.retryDelay);
      await tester.pump();
      expect(screen.seen, ['error: blip'], reason: 'said once, not each try');

      backend.failure = null;
      await tester.pump(backend.sync.retryDelay * 2);
      await tester.pump();
      expect(screen.seen, ['error: blip', 'submitted']);
    });

    liveTest('for a lasting reason is shown, and the same rows come back '
        'once it is over', (tester, backend) async {
      final screen = _Screen(backend.watch());
      await tester.pump();

      backend.failure = _Refusal();
      await backend.sync.resync();
      await tester.pump();
      expect(screen.seen, ['submitted', 'error: refused']);

      backend.failure = null;
      await tester.pump(backend.sync.retryDelay);
      await tester.pump();
      expect(screen.seen, ['submitted', 'error: refused', 'submitted']);
    });
  });

  group('a view out of sight', () {
    liveTest('reads nothing while paused, and once on coming back if '
        'anything happened', (tester, backend) async {
      final screen = _Screen(backend.watch());
      await tester.pump();
      backend.channel.onStatus(ChangeChannelStatus.subscribed);
      await tester.pump();
      final reads = backend.reads;

      screen.subscription.pause();
      backend.setStatus('inProgress');
      backend.channel
        ..onChange('damage_reports')
        ..onChange('damage_reports');
      await backend.sync.resync();
      await tester.pump(const Duration(minutes: 1));
      expect(backend.reads, reads);

      screen.subscription.resume();
      await tester.pump();

      expect(backend.reads, reads + 1);
      expect(screen.seen.last, 'inProgress');
    });

    liveTest('reads nothing on coming back if nothing happened', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();
      final reads = backend.reads;

      screen.subscription.pause();
      await tester.pump(const Duration(seconds: 5));
      screen.subscription.resume();
      await tester.pump();

      expect(backend.reads, reads);
    });
  });

  group('a navigation button pressed again (2026-11-25)', () {
    liveTest('reads every view on screen again, and says it succeeded', (
      tester,
      backend,
    ) async {
      final reports = _Screen(backend.watch());
      final tools = _Screen(backend.watch('tools'));
      await tester.pump();
      final reads = backend.reads;

      backend.setStatus('approved');
      final done = backend.sync.refreshWatched();
      await tester.pump();

      expect(await done, isTrue);
      expect(backend.reads, reads + 2);
      expect(reports.seen.last, 'approved');
      expect(tools.seen.last, 'approved');
    });

    liveTest('says so when a read fails, and keeps the rows shown', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();

      backend.failure = _Blip();
      final done = backend.sync.refreshWatched();
      await tester.pump();

      expect(await done, isFalse);
      expect(screen.seen, ['submitted'], reason: 'the rows stay');

      // Answered once the connection is back.
      backend.failure = null;
      final again = backend.sync.refreshWatched();
      await tester.pump();
      expect(await again, isTrue);
    });

    liveTest('waits for a slow read, and fails one that never answers', (
      tester,
      backend,
    ) async {
      _Screen(backend.watch());
      await tester.pump();

      backend.holdReads = true;
      var answered = false;
      final done = backend.sync
          .refreshWatched(limit: const Duration(seconds: 3))
          .then((ok) {
            answered = true;
            return ok;
          });
      await tester.pump(const Duration(seconds: 1));
      expect(answered, isFalse, reason: 'past the save settle, still waiting');

      await tester.pump(const Duration(seconds: 3));
      expect(await done, isFalse);
      for (final gate in backend.held) {
        gate.complete();
      }
      await tester.pump();
    });

    liveTest('leaves a view out of sight to be read when it is back', (
      tester,
      backend,
    ) async {
      final screen = _Screen(backend.watch());
      await tester.pump();
      final reads = backend.reads;
      screen.subscription.pause();

      expect(await backend.sync.refreshWatched(), isTrue);
      expect(backend.reads, reads);

      screen.subscription.resume();
      await tester.pump();
      expect(backend.reads, reads + 1);
    });

    liveTest('with nothing on screen, there is nothing to read', (
      tester,
      backend,
    ) async {
      expect(await backend.sync.refreshWatched(), isTrue);
      expect(backend.reads, 0);
    });
  });
}
