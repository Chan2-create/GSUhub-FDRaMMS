import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/data/live_sync.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/services/connectivity_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/damage_reports/presentation/report_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart' show SupabaseClient;

import '../../support/test_app_config.dart';

class _Channel implements ChangeChannel {
  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}

/// The case the live project's log recorded on 2026-11-16: a console
/// signed out (by its idle timer) and signed in again in the same tab,
/// after which nothing saved appeared until the page was reloaded.
///
/// The app's own providers, wired as the app wires them, over a database
/// that is one report behind a mock HTTP client. Only the sign-in, the
/// HTTP client and the Realtime channel are stand-ins.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const administrator = AuthUser(
    uid: 'u-admin',
    email: 'admin@dorsu.edu.ph',
    role: UserRole.admin,
  );
  const actor = AuditActor(id: 'u-admin', name: 'Ramon Dela Cruz');

  late Map<String, dynamic> row;
  late int reads;
  late bool signedIn;
  late List<_Channel> channels;
  late StreamController<AuthUser?> session;
  late ProviderContainer container;

  setUp(() {
    row = {
      'id': 'r-1',
      'reporter_id': 'u-req',
      'reporter_name': 'Maria Santos',
      'title': 'Sparking outlet',
      'description': 'The outlet sparks when used.',
      'requestor_priority': 'high',
      'status': 'submitted',
      'photo_urls': <String>[],
      'dismissed_duplicate_ids': <String>[],
      'submitted_at': '2026-11-16T07:30:00+00:00',
      'updated_at': '2026-11-16T07:30:00+00:00',
    };
    reads = 0;
    signedIn = false;
    channels = [];
    session = StreamController<AuthUser?>();

    http.Response json(http.BaseRequest request, Object? body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
    final client = SupabaseClient(
      'http://localhost:54321',
      'anon-key',
      accessToken: () async => signedIn ? 'token' : null,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path == '/rest/v1/damage_reports') {
          reads++;
          return json(request, [row]);
        }
        if (path == '/rest/v1/rpc/transition_report') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          row = {...row, 'status': sent['to_status']};
          return json(request, null);
        }
        return json(request, <Object>[]);
      }),
    );

    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig()),
        supabaseClientProvider.overrideWithValue(client),
        authStateProvider.overrideWith((ref) => session.stream),
        signedInCheckProvider.overrideWithValue(() => signedIn),
        changeChannelOpenerProvider.overrideWithValue(({
          required onChange,
          required onStatus,
        }) {
          final channel = _Channel();
          channels.add(channel);
          return channel;
        }),
        reachabilityProvider.overrideWith(
          (ref) => const Stream<BackendReachability>.empty(),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await session.close();
      await client.dispose();
    });
  });

  /// The status the Damage Reports list is showing, or null while it has
  /// nothing to show.
  ReportStatus? listed() => switch (container.read(reportsStreamProvider)) {
    AsyncData(value: Success(:final value)) when value.isNotEmpty =>
      value.single.status,
    _ => null,
  };

  void signIn() {
    signedIn = true;
    session.add(administrator);
  }

  void signOut() {
    signedIn = false;
    session.add(null);
  }

  test('after signing out and in again in the same session, the list is '
      'read afresh, hears changes again, and shows a save at once', () async {
    // The console's list, kept for the life of the page.
    final list = container.listen(reportsStreamProvider, (_, _) {});
    addTearDown(list.close);

    signIn();
    await pumpEventQueue();
    expect(listed(), ReportStatus.submitted);
    expect(channels, hasLength(1));

    // Idle for fifteen minutes: signed out, the channel let go.
    signOut();
    await pumpEventQueue();
    expect(channels.single.closed, isTrue);
    final readsSignedOut = reads;

    // Something changes while nobody is signed in.
    row = {...row, 'status': 'underReview'};
    await pumpEventQueue();
    expect(reads, readsSignedOut, reason: 'nothing is read for nobody');

    // They sign back in, in the same tab.
    signIn();
    await pumpEventQueue();

    // Read again for the new sign-in, not left as it was.
    expect(reads, greaterThan(readsSignedOut));
    expect(listed(), ReportStatus.underReview);
    // And listening again.
    expect(channels, hasLength(2));
    expect(channels.last.closed, isFalse);

    // The save that used to land in the database and never on the page.
    final saved = await container
        .read(damageReportRepositoryProvider)
        .transitionStatus(
          reportId: 'r-1',
          to: ReportStatus.approved,
          actor: actor,
        );
    expect(saved.isSuccess, isTrue);
    expect(listed(), ReportStatus.approved);
  });

  test('what was read for one sign-in is not shown to the next', () async {
    final list = container.listen(reportsStreamProvider, (_, _) {});
    addTearDown(list.close);
    signIn();
    await pumpEventQueue();
    expect(listed(), ReportStatus.submitted);

    signOut();
    await pumpEventQueue();

    // Whoever looks now is shown nothing of it.
    expect(listed(), isNull);
  });
}
