import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/data/live_sync.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/errors/supabase_error_mapper.dart';
import 'package:gsuhub/core/services/supabase/supabase_call_guard.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/auth/data/repositories/session_repository_impl.dart';
import 'package:gsuhub/features/damage_reports/data/models/damage_report.dart';
import 'package:gsuhub/features/damage_reports/data/models/report_assessment.dart';
import 'package:gsuhub/features/damage_reports/data/repositories/damage_report_repository_impl.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';

import '../../support/test_app_config.dart';

class _SilentChannel implements ChangeChannel {
  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}

/// A save shows on the page it was made from, whatever Realtime is doing
/// (2026-11-16): the repositories read their live views again once the
/// database has answered, and only then report the result.
///
/// The database here is one report behind a mock HTTP client, and a change
/// channel that never joins and never announces anything: the state the
/// console was in when saved changes stopped appearing until a reload.
void main() {
  const actor = AuditActor(id: 'u-admin', name: 'Ramon Dela Cruz');

  late Map<String, dynamic> row;
  late int reads;
  late List<(String, Map<String, dynamic>)> calls;
  late ({String code, String message})? refusal;
  late bool offline;
  late SupabaseClient client;
  late LiveSync live;
  late DamageReportRepositoryImpl reports;

  http.Response json(
    http.BaseRequest request,
    Object? body, [
    int status = 200,
  ]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
    request: request,
  );

  setUp(() {
    row = {
      'id': 'r-1',
      'reporter_id': 'u-req',
      'reporter_name': 'Maria Santos',
      'title': 'Sparking outlet',
      'description': 'The outlet sparks when used.',
      'requestor_priority': 'high',
      'requestor_category': 'electrical',
      'category': 'electrical',
      'classified_automatically': true,
      'status': 'submitted',
      'photo_urls': <String>[],
      'dismissed_duplicate_ids': <String>[],
      'submitted_at': '2026-11-16T08:00:00.000000+00:00',
      'updated_at': '2026-11-16T08:00:00.123456+00:00',
    };
    reads = 0;
    calls = [];
    refusal = null;
    offline = false;

    client = SupabaseClient(
      'http://localhost:54321',
      'anon-key',
      accessToken: () async => 'token',
      httpClient: MockClient((request) async {
        if (offline) throw http.ClientException('Failed to fetch');
        final path = request.url.path;
        if (path == '/rest/v1/damage_reports') {
          reads++;
          return json(request, [row]);
        }
        if (path.startsWith('/rest/v1/rpc/')) {
          final function = path.substring('/rest/v1/rpc/'.length);
          calls.add((
            function,
            request.body.isEmpty
                ? <String, dynamic>{}
                : jsonDecode(request.body) as Map<String, dynamic>,
          ));
          if (refusal case final refused?) {
            return json(request, {
              'code': refused.code,
              'message': refused.message,
            }, 409);
          }
          if (function == 'transition_report') {
            row = {
              ...row,
              'status': calls.last.$2['to_status'],
              'updated_at': '2026-11-16T08:05:00.000000+00:00',
            };
          }
          return json(request, null);
        }
        return json(request, <Object>[]);
      }),
    );
    addTearDown(client.dispose);

    live = LiveSync(
      openChannel: ({required onChange, required onStatus}) => _SilentChannel(),
      isTransient: SupabaseErrorMapper.isRetryable,
    );
    addTearDown(live.dispose);

    reports = DamageReportRepositoryImpl(
      client: client,
      guard: SupabaseCallGuard(testAppConfig()),
      live: live,
    );
  });

  /// What the page watching the report has been shown.
  List<Result<DamageReport>> watching() {
    final seen = <Result<DamageReport>>[];
    final subscription = reports.watchById('r-1').listen(seen.add);
    addTearDown(subscription.cancel);
    return seen;
  }

  ReportStatus? statusOf(Result<DamageReport> result) =>
      result.fold((report) => report.status, (_) => null);

  test('a status change is on the page by the time the save has answered, '
      'with the live channel silent', () async {
    final seen = watching();
    await pumpEventQueue();
    expect(statusOf(seen.single), ReportStatus.submitted);

    final result = await reports.transitionStatus(
      reportId: 'r-1',
      to: ReportStatus.underReview,
      actor: actor,
    );

    expect(result.isSuccess, isTrue);
    // No waiting, and no reload: it is already there.
    expect(statusOf(seen.last), ReportStatus.underReview);
  });

  test('the list and the open report both show it', () async {
    final seen = watching();
    final lists = <Result<List<DamageReport>>>[];
    final subscription = reports.watchAll().listen(lists.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await reports.transitionStatus(
      reportId: 'r-1',
      to: ReportStatus.underReview,
      actor: actor,
    );

    expect(statusOf(seen.last), ReportStatus.underReview);
    expect(
      lists.last.fold((list) => list.single.status, (_) => null),
      ReportStatus.underReview,
    );
  });

  test('a save that cannot reach the server says so, and leaves the page '
      'as it was', () async {
    final seen = watching();
    await pumpEventQueue();
    offline = true;

    final result = await reports.transitionStatus(
      reportId: 'r-1',
      to: ReportStatus.underReview,
      actor: actor,
    );

    expect(
      result,
      isA<Error<void>>().having(
        (error) => error.failure,
        'failure',
        isA<NetworkFailure>().having(
          (failure) => failure.message,
          'message',
          contains('Cannot reach the server'),
        ),
      ),
    );
    await pumpEventQueue();
    expect(seen, hasLength(1), reason: 'no error over the report on screen');
    expect(statusOf(seen.single), ReportStatus.submitted);

    // The connection returns, and trying again works.
    offline = false;
    final retried = await reports.transitionStatus(
      reportId: 'r-1',
      to: ReportStatus.underReview,
      actor: actor,
    );
    expect(retried.isSuccess, isTrue);
    expect(statusOf(seen.last), ReportStatus.underReview);
  });

  test('a save the database refuses shows what the database holds', () async {
    final seen = watching();
    await pumpEventQueue();

    // Someone else approved it meanwhile; this page had not heard.
    row = {...row, 'status': 'approved'};
    refusal = (
      code: 'PT409',
      message: 'A report cannot move from APPROVED to UNDER REVIEW.',
    );

    final result = await reports.transitionStatus(
      reportId: 'r-1',
      to: ReportStatus.underReview,
      actor: actor,
    );

    expect(
      result,
      isA<Error<void>>().having(
        (error) => error.failure.message,
        'message',
        'A report cannot move from APPROVED to UNDER REVIEW.',
      ),
    );
    expect(statusOf(seen.last), ReportStatus.approved);
  });

  test('a review says which version of the report it was made from, and '
      'carries its reason', () async {
    final seen = watching();
    await pumpEventQueue();
    final report = seen.single.fold((report) => report, (_) => null)!;

    await reports.recordAssessment(
      reportId: 'r-1',
      assessment: ReportAssessment(
        category: DamageCategory.plumbing,
        classifiedAutomatically: false,
        severityRating: 4,
        safetyRiskRating: 4,
        frequencyRating: 3,
        locationImportanceRating: 3,
        priorityScore: 3.7,
        recommendedPriority: PriorityLevel.critical,
        officialPriority: PriorityLevel.critical,
        reason: '  A burst pipe behind the outlet.  ',
      ),
      actor: actor,
      basedOnUpdate: report.updatedAt,
    );

    final (function, sent) = calls.single;
    expect(function, 'record_assessment');
    expect(sent['reason'], 'A burst pipe behind the outlet.');
    // Within the database's millisecond of grace of what it stored.
    final expected = DateTime.parse(sent['expected_updated_at'] as String);
    final stored = DateTime.parse(row['updated_at'] as String);
    expect(expected.difference(stored).inMicroseconds.abs(), lessThan(1000));
    // What the requestor chose is not among what is sent.
    expect(sent.keys, isNot(contains('requestor_priority')));
    expect(sent.keys, isNot(contains('requestor_category')));
  });

  test('the keep-alive does not set every page reading again', () async {
    watching();
    await pumpEventQueue();
    final before = reads;

    await SessionRepositoryImpl(
      client: client,
      guard: SupabaseCallGuard(testAppConfig()),
      live: live,
    ).touch();
    await pumpEventQueue();

    expect(reads, before);
  });
}
