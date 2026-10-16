import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/services/supabase/supabase_session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A stand-in for the signed-in Firebase user: hands out numbered ID
/// tokens and remembers whether a fresh one was asked for.
class _FakeUser {
  _FakeUser(this.uid);

  final String uid;
  int issued = 0;
  int forced = 0;

  SessionUser get handle => (
    uid: uid,
    idToken: ({bool forceRefresh = false}) async {
      if (forceRefresh) forced++;
      issued++;
      return 'firebase-$uid-$issued';
    },
  );
}

void main() {
  final start = DateTime.utc(2026, 10, 16, 8);
  late DateTime now;
  late _FakeUser? user;
  late List<Map<String, Object?>> requests;
  late int Function(String idToken) lifetimeFor;
  late StreamController<String?> uids;

  SupabaseSession session({http.Client? client}) {
    final subject = SupabaseSession(
      exchangeUrl: Uri.parse(
        'http://localhost:54321/functions/v1/firebase-token-exchange',
      ),
      apiKey: 'anon-key',
      currentUser: () => user?.handle,
      uidChanges: uids.stream,
      clock: () => now,
      httpClient:
          client ??
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            requests.add({
              'apikey': request.headers['apikey'],
              'idToken': body['idToken'],
            });
            final idToken = body['idToken']! as String;
            final expiresAt =
                now.millisecondsSinceEpoch ~/ 1000 + lifetimeFor(idToken);
            return http.Response(
              jsonEncode({
                'access_token': 'supabase-for-$idToken',
                'token_type': 'bearer',
                'expires_at': expiresAt,
              }),
              200,
            );
          }),
    );
    addTearDown(subject.dispose);
    return subject;
  }

  setUp(() {
    now = start;
    user = _FakeUser('seed-faculty-0001');
    requests = [];
    lifetimeFor = (_) => 3600;
    uids = StreamController<String?>.broadcast(sync: true);
  });

  tearDown(() => uids.close());

  test('signed out: no token, and no call to the exchange', () async {
    user = null;
    final subject = session();
    expect(await subject.accessToken(), isNull);
    expect(requests, isEmpty);
  });

  test('trades the Firebase ID token, sending the API key', () async {
    final subject = session();
    expect(
      await subject.accessToken(),
      'supabase-for-firebase-seed-faculty-0001-1',
    );
    expect(requests, [
      {'apikey': 'anon-key', 'idToken': 'firebase-seed-faculty-0001-1'},
    ]);
  });

  test('answers from the cache until the token nears expiry', () async {
    final subject = session();
    final first = await subject.accessToken();
    now = start.add(const Duration(minutes: 50));
    expect(await subject.accessToken(), first);
    expect(requests, hasLength(1));

    // Within a minute of expiry it is replaced.
    now = start.add(const Duration(minutes: 59, seconds: 30));
    expect(await subject.accessToken(), isNot(first));
    expect(requests, hasLength(2));
  });

  test('concurrent callers share one exchange', () async {
    final subject = session();
    final tokens = await Future.wait([
      subject.accessToken(),
      subject.accessToken(),
      subject.accessToken(),
    ]);
    expect(tokens.toSet(), hasLength(1));
    expect(requests, hasLength(1));
  });

  test('a Firebase token about to expire is refreshed first', () async {
    // The first ID token has 30 s left, so its Supabase token would be
    // stale on arrival; the refreshed one has the full hour.
    lifetimeFor = (idToken) => idToken.endsWith('-1') ? 30 : 3600;
    final subject = session();
    expect(
      await subject.accessToken(),
      'supabase-for-firebase-seed-faculty-0001-2',
    );
    expect(user!.forced, 1);
  });

  test('another account signing in gets its own token', () async {
    final subject = session();
    final first = await subject.accessToken();
    user = _FakeUser('seed-admin-0001');
    final second = await subject.accessToken();
    expect(second, 'supabase-for-firebase-seed-admin-0001-1');
    expect(second, isNot(first));
  });

  test('tells live updates of each new token, and of signing out', () async {
    final subject = session();
    final told = <String?>[];
    subject.onTokenChanged = told.add;

    await subject.accessToken();
    user = null;
    uids.add(null);
    expect(told, ['supabase-for-firebase-seed-faculty-0001-1', null]);
  });

  test('signing in trades straight away', () async {
    user = null;
    final subject = session();
    final told = <String?>[];
    subject.onTokenChanged = told.add;

    user = _FakeUser('seed-faculty-0001');
    uids.add('seed-faculty-0001');
    await pumpEventQueue();
    expect(told, ['supabase-for-firebase-seed-faculty-0001-1']);
  });

  test('a refused Firebase token means signing in again', () async {
    final subject = session(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': 'invalid_token',
            'message': 'The token has expired.',
          }),
          401,
        ),
      ),
    );
    await expectLater(
      subject.accessToken(),
      throwsA(
        isA<SupabaseSessionException>()
            .having((e) => e.rejected, 'rejected', isTrue)
            .having((e) => e.message, 'message', 'The token has expired.'),
      ),
    );
  });

  test('an exchange that is down is worth retrying, not a sign-out', () async {
    final subject = session(
      client: MockClient((_) async => http.Response('Bad gateway', 502)),
    );
    await expectLater(
      subject.accessToken(),
      throwsA(
        isA<SupabaseSessionException>().having(
          (e) => e.rejected,
          'rejected',
          isFalse,
        ),
      ),
    );
  });

  test('the next call after a failure tries again', () async {
    var calls = 0;
    final subject = session(
      client: MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('{}', 503);
        return http.Response(
          jsonEncode({
            'access_token': 'second-try',
            'expires_at': now.millisecondsSinceEpoch ~/ 1000 + 3600,
          }),
          200,
        );
      }),
    );
    await expectLater(subject.accessToken(), throwsA(anything));
    expect(await subject.accessToken(), 'second-try');
  });
}
