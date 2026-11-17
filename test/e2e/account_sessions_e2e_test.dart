// Ending sessions and the departments list, end to end against the local
// Supabase stack (2026-11-17): that the reason a session ended reaches the
// app through the API (the refusal's hint), and that the list is readable
// signed out.
//
//   npx supabase start
//   npx supabase migration up            # or: npx supabase db reset
//   $env:SUPABASE_E2E = '1'              # PowerShell; export SUPABASE_E2E=1 elsewhere
//   flutter test test/e2e
//
// Skipped unless SUPABASE_E2E is 1. LOCAL ONLY, like supabase_flows_test:
// it signs its own tokens with the local stack's JWT secret. It changes a
// seeded account and puts it back.
@Tags(['e2e'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/config/session_policy.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/supabase/supabase_call_guard.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/auth/data/repositories/session_repository_impl.dart';
import 'package:gsuhub/features/user_management/data/repositories/department_repository_impl.dart';
import 'package:gsuhub/features/user_management/data/repositories/user_repository_impl.dart';
import 'package:supabase/supabase.dart';

import '../support/test_app_config.dart';

const admin = AuditActor(id: 'seed-admin-0001', name: 'Ramon Dela Cruz');

/// A seeded faculty account this test changes, and restores.
const subject = 'seed-faculty-0003';

final bool enabled = Platform.environment['SUPABASE_E2E'] == '1';
const _skip = 'Needs the local stack: set SUPABASE_E2E=1.';

Map<String, String> _localStack() {
  final status = Process.runSync('npx', [
    'supabase',
    'status',
    '-o',
    'env',
  ], runInShell: true);
  if (status.exitCode != 0) {
    throw StateError('The local stack is not running: ${status.stderr}');
  }
  final values = <String, String>{};
  for (final line in const LineSplitter().convert(status.stdout as String)) {
    final equals = line.indexOf('=');
    if (equals < 0) continue;
    values[line.substring(0, equals).trim()] = line
        .substring(equals + 1)
        .trim()
        .replaceAll('"', '');
  }
  final host = Uri.parse(values['API_URL'] ?? '').host;
  if (host != '127.0.0.1' && host != 'localhost') {
    throw StateError('Refusing: ${values['API_URL']} is not the local stack.');
  }
  return values;
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// A token like the exchange's, for a sign-in [signedInAgo] ago.
String _tokenFor(String uid, String secret, Duration signedInAgo) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final header = _base64Url(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payload = _base64Url(
    utf8.encode(
      jsonEncode({
        'sub': uid,
        'role': 'authenticated',
        'aud': 'authenticated',
        'auth_time': now - signedInAgo.inSeconds,
        'iat': now,
        'exp': now + 600,
      }),
    ),
  );
  final signature = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode('$header.$payload'));
  return '$header.$payload.${_base64Url(signature.bytes)}';
}

T _value<T>(Result<T> result) => result.fold(
  (value) => value,
  (failure) => throw TestFailure('Expected success, got $failure'),
);

void main() {
  late Map<String, String> stack;
  late SupabaseCallGuard guard;
  final clients = <SupabaseClient>[];

  SupabaseClient clientFor(String? uid, {Duration ago = Duration.zero}) {
    final client = SupabaseClient(
      stack['API_URL']!,
      stack['ANON_KEY']!,
      accessToken: () async =>
          uid == null ? null : _tokenFor(uid, stack['JWT_SECRET']!, ago),
    );
    clients.add(client);
    return client;
  }

  setUpAll(() {
    if (!enabled) return;
    stack = _localStack();
    guard = SupabaseCallGuard(
      testAppConfig(
        supabaseUrl: stack['API_URL']!,
        supabaseAnonKey: stack['ANON_KEY']!,
        requestTimeout: const Duration(seconds: 20),
      ),
    );
  });

  tearDownAll(() async {
    for (final client in clients) {
      await client.dispose();
    }
  });

  test(
    'a deactivated account is told why on its next call, through the API',
    skip: enabled ? false : _skip,
    () async {
      final accounts = UserRepositoryImpl(
        client: clientFor(admin.id),
        guard: guard,
      );
      // Signed in a minute ago, before the administrator acts.
      final theirs = SessionRepositoryImpl(
        client: clientFor(subject, ago: const Duration(minutes: 1)),
        guard: guard,
      );
      expect(_value(await theirs.state()), isNull, reason: 'active');

      _value(
        await accounts.setAccountStatus(
          subject,
          AccountStatus.inactive,
          actor: admin,
        ),
      );
      addTearDown(
        () => accounts.setAccountStatus(
          subject,
          AccountStatus.active,
          actor: admin,
        ),
      );

      expect(_value(await theirs.state()), SessionEndReason.deactivated);
      final touched = await theirs.touch();
      final failure = touched.fold((_) => null, (failure) => failure);
      expect(
        failure,
        isA<SessionExpiredFailure>()
            .having((f) => f.reason, 'reason', SessionEndReason.deactivated)
            .having(
              (f) => f.message,
              'message',
              SessionPolicy.deactivatedMessage,
            ),
      );
    },
  );

  test(
    'a role change ends the old sign-in; a new one has the new role',
    skip: enabled ? false : _skip,
    () async {
      final accounts = UserRepositoryImpl(
        client: clientFor(admin.id),
        guard: guard,
      );
      final before = _value(await accounts.getById(subject));
      final oldSession = SessionRepositoryImpl(
        client: clientFor(subject, ago: const Duration(minutes: 1)),
        guard: guard,
      );

      _value(
        await accounts.updateAccount(
          updated: before.copyWith(role: UserRole.maintenancePersonnel),
          actor: admin,
        ),
      );
      addTearDown(() => accounts.updateAccount(updated: before, actor: admin));

      expect(_value(await oldSession.state()), SessionEndReason.roleChanged);
      // Signing in again: a sign-in from after the change.
      await Future<void>.delayed(const Duration(seconds: 2));
      final newSession = SessionRepositoryImpl(
        client: clientFor(subject),
        guard: guard,
      );
      expect(_value(await newSession.state()), isNull);
    },
  );

  test(
    'the departments list is readable signed out, and only administrators '
    'change it',
    skip: enabled ? false : _skip,
    () async {
      final asAdmin = DepartmentRepositoryImpl(
        client: clientFor(admin.id),
        guard: guard,
      );
      final name = 'E2E Department ${DateTime.now().millisecondsSinceEpoch}';
      final id = _value(await asAdmin.create(name));
      addTearDown(() => asAdmin.setActive(id, active: false));

      final signedOut = DepartmentRepositoryImpl(
        client: clientFor(null),
        guard: guard,
      );
      expect(
        _value(await signedOut.getActive()).map((d) => d.name),
        contains(name),
      );

      final asFaculty = DepartmentRepositoryImpl(
        client: clientFor('seed-faculty-0001'),
        guard: guard,
      );
      expect(
        (await asFaculty.create('Mine')).fold((_) => null, (f) => f),
        isA<PermissionFailure>(),
      );
    },
  );
}
