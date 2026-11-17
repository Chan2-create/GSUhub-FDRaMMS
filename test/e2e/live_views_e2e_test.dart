// Live views and the review trail, end to end against the local Supabase
// stack (2026-11-16): the real Realtime channel, row level security on what
// it delivers, and the real `record_assessment`.
//
//   npx supabase start
//   npx supabase migration up            # or: npx supabase db reset
//   $env:SUPABASE_E2E = '1'              # PowerShell; export SUPABASE_E2E=1 elsewhere
//   flutter test test/e2e
//
// Skipped unless SUPABASE_E2E is 1. LOCAL ONLY, like supabase_flows_test:
// it signs its own tokens with the local stack's JWT secret.
@Tags(['e2e'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/data/live_sync.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/services/supabase/supabase_call_guard.dart';
import 'package:gsuhub/core/services/supabase/supabase_change_channel.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/audit/data/repositories/audit_log_repository_impl.dart';
import 'package:gsuhub/features/damage_reports/data/models/damage_report.dart';
import 'package:gsuhub/features/damage_reports/data/models/report_assessment.dart';
import 'package:gsuhub/features/damage_reports/data/models/report_submission.dart';
import 'package:gsuhub/features/damage_reports/data/repositories/damage_report_repository_impl.dart';
import 'package:supabase/supabase.dart';

import '../support/test_app_config.dart';

/// Seeded accounts and records (tool/seed.dart).
const requestor = AuditActor(id: 'seed-faculty-0001', name: 'Maria Santos');
const admin = AuditActor(id: 'seed-admin-0001', name: 'Ramon Dela Cruz');
const otherAdmin = AuditActor(id: 'seed-admin-0002', name: 'Second admin');
const facilityId = 'fac-engineering';

final bool enabled = Platform.environment['SUPABASE_E2E'] == '1';
const _skip = 'Needs the local stack: set SUPABASE_E2E=1.';

/// API_URL, ANON_KEY and JWT_SECRET of the running local stack.
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

/// A token like the ones firebase-token-exchange issues, signed in now.
String _tokenFor(String uid, String secret) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final header = _base64Url(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payload = _base64Url(
    utf8.encode(
      jsonEncode({
        'sub': uid,
        'role': 'authenticated',
        'aud': 'authenticated',
        'auth_time': now,
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

/// Waits until [met], or fails saying what was being waited for.
Future<void> _eventually(
  String what,
  bool Function() met, {
  Duration within = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(within);
  while (!met()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Waited ${within.inSeconds}s for: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  late Map<String, String> stack;
  late SupabaseCallGuard guard;
  final clients = <SupabaseClient>[];
  final syncs = <LiveSync>[];

  /// A client of its own each time: its own Realtime connection, as a
  /// second browser has.
  SupabaseClient clientFor(String uid) {
    final client = SupabaseClient(
      stack['API_URL']!,
      stack['ANON_KEY']!,
      accessToken: () async => _tokenFor(uid, stack['JWT_SECRET']!),
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
        maxRetryAttempts: 1,
      ),
    );
  });

  tearDownAll(() async {
    for (final sync in syncs) {
      sync.dispose();
    }
    for (final client in clients) {
      await client.dispose();
    }
  });

  /// Files a report as the requestor: High, and Electrical by their choice.
  Future<String> fileReport(String title) async {
    final reports = DamageReportRepositoryImpl(
      client: clientFor(requestor.id),
      guard: guard,
    );
    final id = reports.newReportId();
    _value(
      await reports.submit(
        reportId: id,
        submission: ReportSubmission(
          reporter: requestor,
          title: title,
          description: 'The outlet by the door sparks when used.',
          requestorPriority: PriorityLevel.high,
          requestorCategory: DamageCategory.electrical,
          classifiedCategory: DamageCategory.electrical,
          facilityId: facilityId,
          facilityName: 'Engineering Building',
        ),
      ),
    );
    return id;
  }

  ReportAssessment review({
    DamageCategory category = DamageCategory.plumbing,
    PriorityLevel official = PriorityLevel.critical,
    String? reason,
  }) => ReportAssessment(
    category: category,
    classifiedAutomatically: false,
    severityRating: 4,
    safetyRiskRating: 4,
    frequencyRating: 3,
    locationImportanceRating: 3,
    priorityScore: 3.7,
    recommendedPriority: PriorityLevel.critical,
    officialPriority: official,
    reason: reason,
  );

  test(
    "another administrator's change reaches an open page by itself, and "
    'still does after the channels were closed as a sign-out closes them',
    skip: enabled ? false : _skip,
    () async {
      final reportId = await fileReport('End-to-end: live views');

      // One administrator's page is open on the report and on the list.
      final pageClient = clientFor(admin.id);
      final live = supabaseLiveSync(pageClient);
      syncs.add(live);
      final page = DamageReportRepositoryImpl(
        client: pageClient,
        guard: guard,
        live: live,
      );
      final seen = <ReportStatus>[];
      final listed = <ReportStatus?>[];
      final subscriptions = [
        page.watchById(reportId).listen((r) => seen.add(_value(r).status)),
        page.watchAll().listen(
          (r) => listed.add(
            _value(r)
                .where((report) => report.id == reportId)
                .firstOrNull
                ?.status,
          ),
        ),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });
      await _eventually('the page to load', () => seen.isNotEmpty);
      await _eventually('the channel to join', () => live.isLive);
      expect(seen.last, ReportStatus.submitted);

      // Another administrator, in another browser, starts the review.
      final elsewhere = DamageReportRepositoryImpl(
        client: clientFor(otherAdmin.id),
        guard: guard,
      );
      _value(
        await elsewhere.transitionStatus(
          reportId: reportId,
          to: ReportStatus.underReview,
          actor: otherAdmin,
        ),
      );
      // Well inside the 20 seconds the fallback timer would take, were the
      // channel not delivering.
      await _eventually(
        'the review to show on the open page',
        () => seen.last == ReportStatus.underReview,
        within: const Duration(seconds: 10),
      );
      await _eventually(
        'the review to show in the open list',
        () => listed.last == ReportStatus.underReview,
        within: const Duration(seconds: 10),
      );

      // Once the server's change stream is running, a change is announced
      // over the channel itself: the page hears of it, it does not go and
      // look.
      await Future<void>.delayed(live.joinRecheck);
      final heardWarm = live.changesHeard;
      _value(
        await elsewhere.recordAssessment(
          reportId: reportId,
          assessment: review(),
          actor: otherAdmin,
        ),
      );
      await _eventually(
        'the review to be announced over Realtime',
        () => live.changesHeard > heardWarm,
        within: const Duration(seconds: 10),
      );

      // What a sign-out does to the connection, and what used to leave
      // every page deaf until a reload: every channel is closed.
      await pageClient.removeAllChannels();
      await _eventually('the channel to be noticed gone', () => !live.isLive);
      await _eventually('the channel to be reopened', () => live.isLive);

      _value(
        await elsewhere.transitionStatus(
          reportId: reportId,
          to: ReportStatus.approved,
          actor: otherAdmin,
        ),
      );
      await _eventually(
        'the approval to show on the open page, over the new channel',
        () => seen.last == ReportStatus.approved,
        within: const Duration(seconds: 10),
      );
    },
  );

  test(
    'a save shows on the page it was made from at once, and the requestor '
    'watching their own report hears of it too',
    skip: enabled ? false : _skip,
    () async {
      final reportId = await fileReport('End-to-end: own save');

      final requestorClient = clientFor(requestor.id);
      final requestorLive = supabaseLiveSync(requestorClient);
      syncs.add(requestorLive);
      final mine = <ReportStatus>[];
      final watching =
          DamageReportRepositoryImpl(
                client: requestorClient,
                guard: guard,
                live: requestorLive,
              )
              .watchByReporter(requestor.id)
              .listen(
                (r) => mine.add(
                  _value(r)
                      .firstWhere((report) => report.id == reportId)
                      .status,
                ),
              );
      addTearDown(watching.cancel);
      await _eventually('their list to load', () => mine.isNotEmpty);
      await _eventually('their channel to join', () => requestorLive.isLive);

      final adminClient = clientFor(admin.id);
      final adminLive = supabaseLiveSync(adminClient);
      syncs.add(adminLive);
      final page = DamageReportRepositoryImpl(
        client: adminClient,
        guard: guard,
        live: adminLive,
      );
      final seen = <ReportStatus>[];
      final open = page
          .watchById(reportId)
          .listen((r) => seen.add(_value(r).status));
      addTearDown(open.cancel);
      await _eventually('the page to load', () => seen.isNotEmpty);

      _value(
        await page.transitionStatus(
          reportId: reportId,
          to: ReportStatus.underReview,
          actor: admin,
        ),
      );
      // No waiting: the save's answer comes after the page has the row.
      expect(seen.last, ReportStatus.underReview);

      await _eventually(
        "the requestor's list to follow",
        () => mine.last == ReportStatus.underReview,
        within: const Duration(seconds: 10),
      );
    },
  );

  test(
    "a review keeps the requestor's choices, records the whole decision, "
    "and is not saved over another administrator's newer one",
    skip: enabled ? false : _skip,
    () async {
      final reportId = await fileReport('End-to-end: review trail');
      final first = DamageReportRepositoryImpl(
        client: clientFor(admin.id),
        guard: guard,
      );
      final second = DamageReportRepositoryImpl(
        client: clientFor(otherAdmin.id),
        guard: guard,
      );

      // Both administrators open the report as filed.
      final DamageReport asFiled = _value(await first.getById(reportId));
      expect(asFiled.requestorCategory, DamageCategory.electrical);
      expect(asFiled.requestorPriority, PriorityLevel.high);
      expect(asFiled.officialPriority, isNull);
      expect(asFiled.officialCategory, isNull);
      expect(asFiled.awaitsAssessment, isTrue);

      // The first reviews it: a different type, a higher priority, a reason.
      _value(
        await first.recordAssessment(
          reportId: reportId,
          assessment: review(reason: 'A burst pipe behind the outlet.'),
          actor: admin,
          basedOnUpdate: asFiled.updatedAt,
        ),
      );

      // The second, still looking at the report as filed, saves another.
      final stale = await second.recordAssessment(
        reportId: reportId,
        assessment: review(
          category: DamageCategory.electrical,
          official: PriorityLevel.low,
        ),
        actor: otherAdmin,
        basedOnUpdate: asFiled.updatedAt,
      );
      expect(
        stale.fold((_) => null, (failure) => failure.message),
        allOf(
          contains('changed this report after you opened it here'),
          contains('The latest details are shown now'),
        ),
      );

      final reviewed = _value(await second.getById(reportId));
      // The first decision stands, and what the requestor chose is as filed.
      expect(reviewed.officialCategory, DamageCategory.plumbing);
      expect(reviewed.officialPriority, PriorityLevel.critical);
      expect(reviewed.requestorCategory, DamageCategory.electrical);
      expect(reviewed.requestorPriority, PriorityLevel.high);
      expect(reviewed.reviewedBy, admin.id);

      // With the latest version read, the second may change it.
      _value(
        await second.recordAssessment(
          reportId: reportId,
          assessment: review(official: PriorityLevel.high),
          actor: otherAdmin,
          basedOnUpdate: reviewed.updatedAt,
        ),
      );
      // And saying the same again is not a second decision.
      _value(
        await second.recordAssessment(
          reportId: reportId,
          assessment: review(official: PriorityLevel.high),
          actor: otherAdmin,
          basedOnUpdate: reviewed.updatedAt,
        ),
      );

      final trail = _value(
        await AuditLogRepositoryImpl(
          client: clientFor(admin.id),
          guard: guard,
        ).getForEntity(entityType: 'damage_reports', entityId: reportId),
      ).where((entry) => entry.changes?['officialPriority'] != null).toList();
      expect(trail, hasLength(2));
      // Newest first.
      final [later, earlier] = trail;
      expect(earlier.actorId, admin.id);
      expect(
        earlier.description,
        endsWith('Reason: A burst pipe behind the outlet.'),
      );
      expect(earlier.changes!['requestor'], {
        'category': 'electrical',
        'priority': 'high',
      });
      expect(earlier.changes!['category'], {
        'from': 'electrical',
        'to': 'plumbing',
      });
      expect(earlier.changes!['officialPriority'], {
        'from': null,
        'to': 'critical',
      });
      expect(later.actorId, otherAdmin.id);
      expect(later.changes!['officialPriority'], {
        'from': 'critical',
        'to': 'high',
      });
      expect(later.changes!['requestor'], {
        'category': 'electrical',
        'priority': 'high',
      });
    },
  );
}
