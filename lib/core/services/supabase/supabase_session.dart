import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// The signed-in Firebase user, as far as the session needs to know: who,
/// and how to get a fresh ID token.
typedef SessionUser = ({
  String uid,
  Future<String?> Function({bool forceRefresh}) idToken,
});

/// The token exchange could not give a Supabase token.
class SupabaseSessionException implements Exception {
  const SupabaseSessionException(this.message, {required this.rejected});

  final String message;

  /// The exchange refused the Firebase token: signing in again is the fix.
  /// Otherwise it could not be reached or failed, and a retry may work.
  final bool rejected;

  @override
  String toString() => 'SupabaseSessionException($message)';
}

/// Supabase access tokens for whoever is signed in to Firebase.
///
/// Sign-in stays with Firebase Auth. Supabase learns who is calling from a
/// token that `firebase-token-exchange` mints in return for the Firebase ID
/// token: its `sub` is the Firebase uid, and the database reads the role
/// and account status from the `users` row with that id. This class does
/// the trading. It is the Supabase client's `accessToken` callback, which
/// the client calls before every request, so it answers from a cache and
/// trades only when the cached token is about to run out.
///
/// Signed out, it returns `null` and the client falls back to the anon
/// key, which the database lets read nothing.
class SupabaseSession {
  SupabaseSession({
    required this._exchangeUrl,
    required this._apiKey,
    required this._currentUser,
    Stream<String?>? uidChanges,
    http.Client? httpClient,
    DateTime Function()? clock,
  }) : _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now {
    _uidSubscription = uidChanges?.listen(_onUidChanged);
  }

  /// The session for [auth]'s signed-in user, trading at the
  /// `firebase-token-exchange` function of the project at [supabaseUrl].
  factory SupabaseSession.forFirebase({
    required FirebaseAuth auth,
    required String supabaseUrl,
    required String apiKey,
    http.Client? httpClient,
  }) => SupabaseSession(
    exchangeUrl: Uri.parse('$supabaseUrl/functions/v1/firebase-token-exchange'),
    apiKey: apiKey,
    currentUser: () {
      final user = auth.currentUser;
      if (user == null) return null;
      return (
        uid: user.uid,
        idToken: ({bool forceRefresh = false}) => user.getIdToken(forceRefresh),
      );
    },
    uidChanges: auth.idTokenChanges().map((user) => user?.uid),
    httpClient: httpClient,
  );

  /// How long before expiry a token is replaced. Long enough that a
  /// request started with it does not arrive expired.
  static const Duration refreshMargin = Duration(seconds: 60);

  final Uri _exchangeUrl;
  final String _apiKey;
  final SessionUser? Function() _currentUser;
  final http.Client _http;
  final DateTime Function() _clock;

  StreamSubscription<String?>? _uidSubscription;
  ({String uid, String token, DateTime expiresAt})? _cached;
  ({String uid, Future<String> token})? _inFlight;
  Timer? _refreshTimer;

  /// Told of every new token, and of `null` on sign-out. Live updates use
  /// it: the Realtime connection keeps the token it joined with until it is
  /// handed a new one.
  void Function(String? token)? onTokenChanged;

  /// The token for the signed-in user, or `null` when nobody is.
  Future<String?> accessToken() async {
    final user = _currentUser();
    if (user == null) {
      _forget();
      return null;
    }
    final cached = _cached;
    if (cached != null &&
        cached.uid == user.uid &&
        cached.expiresAt.isAfter(_clock().add(refreshMargin))) {
      return cached.token;
    }
    // The client calls this concurrently; one exchange serves them all.
    final inFlight = _inFlight;
    if (inFlight != null && inFlight.uid == user.uid) return inFlight.token;
    final token = _exchange(user);
    _inFlight = (uid: user.uid, token: token);
    try {
      return await token;
    } finally {
      if (identical(_inFlight?.token, token)) _inFlight = null;
    }
  }

  Future<String> _exchange(SessionUser user) async {
    var minted = await _trade(await user.idToken());
    // A Firebase token minutes from expiry yields a Supabase token that
    // would be stale on arrival. Firebase refreshes its own token only in
    // its last five minutes, so ask for a new one and trade again.
    if (!minted.expiresAt.isAfter(_clock().add(refreshMargin))) {
      minted = await _trade(await user.idToken(forceRefresh: true));
    }
    // Signed out, or someone else signed in, while this was in flight.
    if (_currentUser()?.uid != user.uid) {
      throw const SupabaseSessionException(
        'The signed-in account changed. Try again.',
        rejected: false,
      );
    }
    _cached = (uid: user.uid, token: minted.token, expiresAt: minted.expiresAt);
    _scheduleRefresh(minted.expiresAt);
    onTokenChanged?.call(minted.token);
    return minted.token;
  }

  Future<({String token, DateTime expiresAt})> _trade(String? idToken) async {
    if (idToken == null || idToken.isEmpty) {
      throw const SupabaseSessionException(
        'Sign in again to continue.',
        rejected: true,
      );
    }
    final response = await _http.post(
      _exchangeUrl,
      headers: {'apikey': _apiKey, 'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw SupabaseSessionException(
        'The token exchange answered ${response.statusCode} with no token.',
        rejected: false,
      );
    }
    if (response.statusCode == 200 &&
        body is Map &&
        body['access_token'] is String &&
        body['expires_at'] is num) {
      return (
        token: body['access_token'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (body['expires_at'] as num).toInt() * 1000,
          isUtc: true,
        ),
      );
    }
    final message = body is Map && body['message'] is String
        ? body['message'] as String
        : 'The token exchange answered ${response.statusCode}.';
    throw SupabaseSessionException(
      message,
      rejected: response.statusCode == 401 || response.statusCode == 400,
    );
  }

  /// Trades again shortly before the token runs out, so a live connection
  /// is handed its next token before the server closes it.
  void _scheduleRefresh(DateTime expiresAt) {
    _refreshTimer?.cancel();
    final wait = expiresAt.difference(_clock()) - refreshMargin;
    _refreshTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      unawaited(accessToken().then((_) {}, onError: (Object _) {}));
    });
  }

  void _onUidChanged(String? uid) {
    final cached = _cached;
    if (cached != null && cached.uid == uid) return;
    final hadUser = cached != null;
    _forget();
    if (uid == null) {
      if (hadUser) onTokenChanged?.call(null);
      return;
    }
    // Someone signed in: trade now, so live connections switch to them.
    unawaited(accessToken().then((_) {}, onError: (Object _) {}));
  }

  void _forget() {
    _cached = null;
    _inFlight = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void dispose() {
    _forget();
    unawaited(_uidSubscription?.cancel());
    _uidSubscription = null;
    onTokenChanged = null;
    _http.close();
  }
}
