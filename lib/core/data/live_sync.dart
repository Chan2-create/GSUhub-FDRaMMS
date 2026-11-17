import 'dart:async';
import 'dart:convert';

/// Rows as the database returns them.
typedef LiveRows = List<Map<String, dynamic>>;

/// What an open change channel reports of itself.
enum ChangeChannelStatus {
  /// Joined: changes are being delivered.
  subscribed,

  /// Lost, refused or timed out. Nothing is being delivered.
  interrupted,

  /// Ended, by the server or by a sign-out.
  closed,
}

/// One open subscription to the database's row changes.
abstract interface class ChangeChannel {
  /// Stops listening. Safe to call more than once.
  Future<void> close();
}

/// Opens a [ChangeChannel]. [onChange] hears the table of every row change
/// the signed-in person may see; [onStatus] hears the channel's health.
typedef ChangeChannelOpener = ChangeChannel Function({
  required void Function(String table) onChange,
  required void Function(ChangeChannelStatus status) onStatus,
});

/// Keeps what the screens show in step with the database (2026-11-16).
///
/// Every live view in the app is a query that is **read again** whenever
/// something says it may have changed, and never a list patched together
/// from change events:
///
///   * a change arriving on the one Realtime channel this keeps open
///     (any row of any table the person may see);
///   * the app itself having just saved something ([changed]), so a save
///     shows at once even with the channel down;
///   * the channel coming back after an interruption, a sign-in, the app or
///     tab returning to the front, the connection returning ([resync]);
///   * a timer, but only while the channel is down.
///
/// Why it replaced `SupabaseClient.stream()`, which the repositories used
/// until then (docs/architecture_decisions.md §42): that stream closes for
/// good on a sign-out, on a token the server found expired, and on a
/// single failed read, and nothing reopened it. The screen kept its last
/// rows and looked alive, while every save after that went to the database
/// and never came back to the page. It also turned a dropped socket into
/// "Cannot reach the server", and patched its rows from change events,
/// so what a page showed depended on what each event carried.
///
/// A read that fails for a passing reason keeps the rows already on
/// screen and is tried again; one that fails with nothing on screen, or
/// for a lasting reason, is shown, and still tried again.
class LiveSync {
  LiveSync({
    required this._openChannel,
    bool Function()? isSignedIn,
    bool Function(Object error)? isTransient,
    this.retryDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(seconds: 30),
    this.pollInterval = const Duration(seconds: 20),
    this.changeDebounce = const Duration(milliseconds: 120),
    this.settleTimeout = const Duration(seconds: 5),
    this.joinRecheck = const Duration(seconds: 5),
    this.idleLinger = const Duration(seconds: 10),
  }) : _isSignedIn = isSignedIn ?? _always,
       _isTransient = isTransient ?? _never;

  final ChangeChannelOpener _openChannel;
  final bool Function() _isSignedIn;
  final bool Function(Object error) _isTransient;

  /// The first wait before a failed read, or a lost channel, is tried
  /// again. Doubles each time, up to [maxRetryDelay].
  final Duration retryDelay;
  final Duration maxRetryDelay;

  /// How often everything on screen is read again while the channel is
  /// down. Not used while it is up.
  final Duration pollInterval;

  /// A burst of changes to one table is one read.
  final Duration changeDebounce;

  /// The longest a save waits for the screens to catch up before it
  /// reports its own result.
  final Duration settleTimeout;

  /// How long after the channel joins everything is read once more. The
  /// server answers a join before its change stream for it is running,
  /// and says nothing of what changes in between: found against the real
  /// stack, where a change made a second after the join never arrived.
  final Duration joinRecheck;

  /// How long the channel is kept after the last view stops being
  /// watched. Pages replace their views all at once (a sign-in, moving
  /// between pages), and leaving and joining again each time would be
  /// work for nothing.
  final Duration idleLinger;

  final Set<_LiveQuery> _queries = {};
  ChangeChannel? _channel;
  int _generation = 0;
  int _channelFailures = 0;
  Timer? _reopenTimer;
  Timer? _pollTimer;
  Timer? _recheckTimer;
  Timer? _idleTimer;
  bool _disposed = false;

  static bool _always() => true;
  static bool _never(Object error) => false;

  /// Whether the change channel is joined. For tests and diagnostics.
  bool get isLive => _subscribed;
  bool _subscribed = false;

  /// How many queries are being watched. For tests and diagnostics.
  int get watchedQueries => _queries.length;

  /// How many changes the channel has announced. For tests and
  /// diagnostics: that a row arrived because it was announced, and not
  /// because something else read it again.
  int get changesHeard => _changesHeard;
  int _changesHeard = 0;

  /// The rows [fetch] returns, now and whenever a row of one of [tables]
  /// may have changed.
  ///
  /// The stream is for one listener. It reads when first listened to,
  /// does nothing while paused (a page out of sight), and reads again on
  /// being resumed if anything happened meanwhile. Rows are only emitted
  /// when they differ from the last ones emitted.
  Stream<LiveRows> watchRows({
    required Set<String> tables,
    required Future<LiveRows> Function() fetch,
  }) => _LiveQuery(this, tables, fetch).stream;

  /// Reads every watched query again, or those on [tables]. Completes when
  /// they have answered, or after [settleTimeout], whichever is first.
  Future<void> resync({Iterable<String>? tables}) async {
    if (_disposed) return;
    final wanted = tables?.toSet();
    final reads = [
      for (final query in _queries.toList())
        if (wanted == null || query.tables.any(wanted.contains))
          query.refresh(),
    ];
    if (reads.isEmpty) return;
    await Future.wait(reads).timeout(settleTimeout, onTimeout: () => const []);
  }

  /// The app has just asked the database to change something, and the
  /// database has answered. [reached] is false when no answer came: the
  /// change may or may not have landed, and the screens are read again
  /// without anyone waiting on it.
  Future<void> changed({bool reached = true}) {
    if (reached) return resync();
    unawaited(resync());
    return Future.value();
  }

  /// Someone signed in, or out. Signed out, the channel is let go and
  /// nothing is read; signed in, it is opened and everything is read.
  void sessionChanged() {
    if (_disposed) return;
    _channelFailures = 0;
    if (!_isSignedIn()) {
      _idleTimer?.cancel();
      _idleTimer = null;
      _dropChannel();
      _stopPolling();
      return;
    }
    _ensureChannel();
    unawaited(resync());
  }

  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _dropChannel();
    _stopPolling();
    for (final query in _queries.toList()) {
      query.close();
    }
    _queries.clear();
  }

  void _add(_LiveQuery query) {
    _idleTimer?.cancel();
    _idleTimer = null;
    _queries.add(query);
    _ensureChannel();
  }

  void _remove(_LiveQuery query) {
    _queries.remove(query);
    // Going altogether: no timer may outlive it.
    if (_disposed || _queries.isNotEmpty) return;
    _stopPolling();
    _idleTimer?.cancel();
    _idleTimer = Timer(idleLinger, () {
      if (_queries.isEmpty) _dropChannel();
    });
  }

  bool get _wanted => !_disposed && _queries.isNotEmpty && _isSignedIn();

  void _ensureChannel() {
    if (!_wanted) return;
    // Until the channel reports itself joined, the timer stands in for it.
    if (!_subscribed) _startPolling();
    if (_channel != null) return;
    _reopenTimer?.cancel();
    _reopenTimer = null;
    final generation = ++_generation;
    try {
      _channel = _openChannel(
        onChange: (table) {
          if (generation == _generation) _onChange(table);
        },
        onStatus: (status) {
          if (generation == _generation) _onStatus(status);
        },
      );
    } on Object {
      _scheduleReopen();
    }
  }

  void _onChange(String table) {
    _changesHeard++;
    for (final query in _queries.toList()) {
      if (query.tables.contains(table)) query.changedSoon();
    }
  }

  void _onStatus(ChangeChannelStatus status) {
    switch (status) {
      case ChangeChannelStatus.subscribed:
        _subscribed = true;
        _channelFailures = 0;
        _stopPolling();
        // Kept for a moment with nothing to watch: nothing to read either.
        if (_queries.isEmpty) return;
        // Whatever changed between the first read and the join, or while
        // the channel was down, was not announced. Nor is what changes in
        // the moments after it: see [joinRecheck].
        unawaited(resync());
        _recheckTimer?.cancel();
        _recheckTimer = Timer(joinRecheck, () {
          if (_subscribed && _wanted) unawaited(resync());
        });
      case ChangeChannelStatus.interrupted:
      case ChangeChannelStatus.closed:
        // A channel that failed is replaced, not waited on: it can report
        // itself joined again and deliver nothing.
        _dropChannel();
        _startPolling();
        _scheduleReopen();
    }
  }

  void _dropChannel() {
    _reopenTimer?.cancel();
    _reopenTimer = null;
    _recheckTimer?.cancel();
    _recheckTimer = null;
    _subscribed = false;
    final channel = _channel;
    _channel = null;
    // Whatever the old channel says from here on is not about this one.
    _generation++;
    if (channel != null) {
      unawaited(channel.close().then((_) {}, onError: (Object _) {}));
    }
  }

  void _scheduleReopen() {
    if (!_wanted) return;
    _reopenTimer?.cancel();
    _reopenTimer = Timer(_backoff(_channelFailures++), _ensureChannel);
  }

  void _startPolling() {
    if (_pollTimer != null || !_wanted || _subscribed) return;
    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (_wanted) unawaited(resync());
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// [retryDelay], doubled [failures] times, up to [maxRetryDelay].
  Duration _backoff(int failures) {
    final shift = failures.clamp(0, 16);
    final delay = retryDelay * (1 << shift);
    return delay > maxRetryDelay ? maxRetryDelay : delay;
  }
}

/// One watched query: its rows, kept current.
class _LiveQuery {
  _LiveQuery(this._sync, this.tables, this._fetch) {
    // Synchronous: rows reach the listener as they are emitted, so when
    // a read has answered, the screen has its rows. A save that waited on
    // the read ([LiveSync.changed]) can then say "saved" over a page that
    // already shows it. Nothing is ever emitted from inside a listener's
    // own call: every emission follows an awaited read.
    _controller = StreamController<LiveRows>(
      sync: true,
      onListen: _start,
      onPause: _pause,
      onResume: _resume,
      onCancel: _stop,
    );
  }

  final LiveSync _sync;
  final Set<String> tables;
  final Future<LiveRows> Function() _fetch;
  late final StreamController<LiveRows> _controller;

  bool _listening = false;
  bool _paused = false;

  /// Something may have changed that has not been read yet.
  bool _stale = false;

  Future<void>? _reading;
  bool _readAgain = false;
  Timer? _retryTimer;
  Timer? _changeTimer;
  int _failures = 0;

  /// The rows last emitted, encoded, so the same rows are not emitted
  /// twice; and whether an error was emitted after them.
  String? _emitted;
  bool _showingError = false;
  String? _emittedError;

  Stream<LiveRows> get stream => _controller.stream;

  bool get _active => _listening && !_paused;

  void _start() {
    _listening = true;
    _sync._add(this);
    unawaited(refresh());
  }

  void _pause() {
    _paused = true;
    if (_retryTimer?.isActive ?? false) _stale = true;
    if (_changeTimer?.isActive ?? false) _stale = true;
    _cancelTimers();
  }

  void _resume() {
    _paused = false;
    if (_stale || _emitted == null || _showingError) unawaited(refresh());
  }

  void _stop() {
    _listening = false;
    _cancelTimers();
    _sync._remove(this);
  }

  /// The owner is going: no more rows.
  void close() {
    _listening = false;
    _cancelTimers();
    if (!_controller.isClosed) unawaited(_controller.close());
  }

  void _cancelTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _changeTimer?.cancel();
    _changeTimer = null;
  }

  /// A row of one of [tables] changed: read again, once the burst is over.
  void changedSoon() {
    if (!_active) {
      _stale = true;
      return;
    }
    _changeTimer?.cancel();
    _changeTimer = Timer(_sync.changeDebounce, () => unawaited(refresh()));
  }

  /// Reads again. Completes when a read that began after this call has
  /// answered, so what was emitted by then is no older than the call.
  Future<void> refresh() {
    if (!_active || !_sync._isSignedIn()) {
      _stale = true;
      return Future.value();
    }
    _cancelTimers();
    final reading = _reading;
    if (reading != null) {
      // The read in flight may have been answered before the change it is
      // being asked about, so it is followed by another. Reads are one
      // after the other, never side by side: a later read's rows are never
      // older than an earlier one's, and nothing older goes over newer.
      _readAgain = true;
      return reading;
    }
    return _reading = _read().whenComplete(() => _reading = null);
  }

  Future<void> _read() async {
    do {
      _readAgain = false;
      _stale = false;
      try {
        _succeeded(await _fetch());
      } on Object catch (error, stack) {
        // Asked again meanwhile: the next read is the one that counts.
        if (!_readAgain) _failed(error, stack);
      }
    } while (_readAgain && _active);
    if (_readAgain) _stale = true;
  }

  void _succeeded(LiveRows rows) {
    if (!_listening || _controller.isClosed) return;
    _failures = 0;
    final encoded = _encode(rows);
    if (encoded == _emitted && !_showingError) return;
    _emitted = encoded;
    _showingError = false;
    _emittedError = null;
    _controller.add(rows);
  }

  void _failed(Object error, StackTrace stack) {
    if (!_listening || _controller.isClosed) return;
    // Signed out while it was being read: nothing to show, and nobody to
    // show it to. Signing in reads it again.
    if (!_sync._isSignedIn()) {
      _stale = true;
      return;
    }
    final keepRows = _emitted != null && _sync._isTransient(error);
    final message = '$error';
    if (!keepRows && message != _emittedError) {
      _showingError = true;
      _emittedError = message;
      _controller.addError(error, stack);
    }
    if (!_active) {
      _stale = true;
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(
      _sync._backoff(_failures++),
      () => unawaited(refresh()),
    );
  }

  static String _encode(LiveRows rows) {
    try {
      return jsonEncode(rows);
    } on Object {
      // Not comparable: treated as new rows every time.
      return '${Object().hashCode}';
    }
  }
}
