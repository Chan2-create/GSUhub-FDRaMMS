// The three flows of Objective 1, end to end against the local Supabase
// stack: the real repositories, the real database functions, row level
// security, Storage and Realtime.
//
//   npx supabase start
//   npx supabase db reset                # the demo data
//   $env:SUPABASE_E2E = '1'              # PowerShell; export SUPABASE_E2E=1 elsewhere
//   flutter test test/e2e
//
// Skipped unless SUPABASE_E2E is 1. LOCAL ONLY: it signs its own tokens
// with the local stack's JWT secret, as firebase-token-exchange would, and
// refuses to run against anything but localhost.

// A cold stack (first token exchange, Realtime's first subscription) can take
// longer than the default 30 seconds on a small machine.
@Tags(['e2e'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/constants/storage_paths.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/location_service.dart';
import 'package:gsuhub/core/services/supabase/supabase_call_guard.dart';
import 'package:gsuhub/core/services/supabase/supabase_storage_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/accomplishment/data/models/material_usage.dart';
import 'package:gsuhub/features/accomplishment/data/repositories/accomplishment_report_repository_impl.dart';
import 'package:gsuhub/features/accomplishment/data/repositories/material_usage_repository_impl.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/audit/data/repositories/audit_log_repository_impl.dart';
import 'package:gsuhub/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:gsuhub/features/inventory/data/repositories/inventory_repository_impl.dart';
import 'package:gsuhub/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:gsuhub/features/reporting/data/models/report_assessment.dart';
import 'package:gsuhub/features/reporting/data/models/report_submission.dart';
import 'package:gsuhub/features/reporting/data/repositories/damage_report_repository_impl.dart';
import 'package:gsuhub/features/user_management/data/repositories/user_repository_impl.dart';
import 'package:gsuhub/features/work_orders/data/repositories/work_order_repository_impl.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import '../support/test_app_config.dart';

/// Seeded accounts and records (tool/seed.dart).
const requestor = AuditActor(id: 'seed-faculty-0001', name: 'Maria Santos');
const otherRequestor = 'seed-faculty-0002';
const admin = AuditActor(id: 'seed-admin-0001', name: 'Ramon Dela Cruz');
const technician = AuditActor(id: 'seed-personnel-0001', name: 'Marcus Wright');
const facilityId = 'fac-engineering';
const material = 'inv-led-bulb';

final bool enabled = Platform.environment['SUPABASE_E2E'] == '1';

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

/// A token like the ones firebase-token-exchange issues.
String _tokenFor(String uid, String secret) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final header = _base64Url(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payload = _base64Url(
    utf8.encode(
      jsonEncode({
        'sub': uid,
        'role': 'authenticated',
        'aud': 'authenticated',
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

/// A 1x1 PNG.
final Uint8List _photo = base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  late Map<String, String> stack;
  late SupabaseCallGuard guard;
  final clients = <String, SupabaseClient>{};

  SupabaseClient clientFor(String uid) => clients.putIfAbsent(
    uid,
    () => SupabaseClient(
      stack['API_URL']!,
      stack['ANON_KEY']!,
      accessToken: () async => _tokenFor(uid, stack['JWT_SECRET']!),
    ),
  );

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
    for (final client in clients.values) {
      await client.dispose();
    }
  });

  // Shared across the three flows, which run in order.
  late String reportId;
  late String workOrderId;

  test(
    'flow 1: a requestor files a report with photos and a geo-tag',
    skip: enabled ? false : 'Needs the local stack: set SUPABASE_E2E=1.',
    () async {
      final client = clientFor(requestor.id);
      final reports = DamageReportRepositoryImpl(client: client, guard: guard);
      final storage = SupabaseStorageService(
        client: client,
        currentUid: () => requestor.id,
        guard: guard,
      );
      reportId = reports.newReportId();

      final urls = [
        for (final name in ['photo-1.png', 'photo-2.png'])
          _value(
            await storage.uploadFile(
              path: StoragePaths.damageReportPhoto(reportId, name),
              bytes: _photo,
            ),
          ),
      ];
      expect(
        urls.first,
        contains('damage_reports/${requestor.id}/$reportId/photo-1.png'),
      );

      _value(
        await reports.submit(
          reportId: reportId,
          submission: ReportSubmission(
            reporter: requestor,
            title: 'End-to-end: dead socket',
            description: 'The socket by the door has no power.',
            requestorPriority: PriorityLevel.medium,
            classifiedCategory: DamageCategory.electrical,
            facilityId: facilityId,
            facilityName: 'Engineering Building',
            coordinates: const GeoCoordinates(
              latitude: 7.0731,
              longitude: 126.2147,
            ),
            photoUrls: urls,
          ),
        ),
      );

      final report = _value(await reports.getById(reportId));
      expect(report.status, ReportStatus.submitted);
      expect(report.reporterName, requestor.name);
      expect(report.coordinates, const GeoPoint(7.0731, 126.2147));
      expect(report.photoUrls, urls);
      expect(report.category, DamageCategory.electrical);

      // The photo is private, but its signed URL opens it.
      expect((await http.get(Uri.parse(urls.first))).statusCode, 200);

      // Another requestor cannot see it at all.
      final hidden = await DamageReportRepositoryImpl(
        client: clientFor(otherRequestor),
        guard: guard,
      ).getById(reportId);
      expect(hidden.fold((_) => null, (f) => f), isA<NotFoundFailure>());

      final notices = await NotificationRepositoryImpl(
        client: client,
        guard: guard,
      ).watchForUser(requestor.id).first;
      expect(
        _value(notices)
            .where((n) => n.relatedEntityId == reportId)
            .map((n) => n.title),
        contains('Report received'),
      );
    },
  );

  test(
    'flow 2: an administrator approves it, and the requestor sees it live',
    skip: enabled ? false : 'Needs the local stack: set SUPABASE_E2E=1.',
    () async {
      final reports = DamageReportRepositoryImpl(
        client: clientFor(admin.id),
        guard: guard,
      );

      // The requestor's screen is watching the report.
      final approvedSeen =
          DamageReportRepositoryImpl(
                client: clientFor(requestor.id),
                guard: guard,
              )
              .watchById(reportId)
              .map(_value)
              .firstWhere((report) => report.status == ReportStatus.approved)
              .timeout(const Duration(seconds: 30));

      _value(
        await reports.transitionStatus(
          reportId: reportId,
          to: ReportStatus.underReview,
          actor: admin,
        ),
      );
      _value(
        await reports.recordAssessment(
          reportId: reportId,
          assessment: ReportAssessment(
            category: DamageCategory.electrical,
            classifiedAutomatically: true,
            severityRating: 3,
            safetyRiskRating: 3,
            frequencyRating: 2,
            locationImportanceRating: 2,
            priorityScore: 2.8,
            recommendedPriority: PriorityLevel.high,
            officialPriority: PriorityLevel.high,
          ),
          actor: admin,
        ),
      );
      _value(
        await reports.transitionStatus(
          reportId: reportId,
          to: ReportStatus.approved,
          actor: admin,
        ),
      );

      expect((await approvedSeen).officialPriority, PriorityLevel.high);

      final trail = _value(
        await AuditLogRepositoryImpl(
          client: clientFor(admin.id),
          guard: guard,
        ).getForEntity(entityType: 'damage_reports', entityId: reportId),
      ).map((entry) => entry.description);
      expect(
        trail,
        containsAll([
          'Submitted "End-to-end: dead socket"',
          'Status changed from PENDING to UNDER REVIEW',
          'Status changed from UNDER REVIEW to APPROVED',
        ]),
      );
      expect(
        trail.any((line) => line.startsWith('Classified as Electrical')),
        isTrue,
      );
    },
  );

  test(
    'flow 3: an administrator assigns it; the technician does the work; '
    'it is signed off and rated',
    skip: enabled ? false : 'Needs the local stack: set SUPABASE_E2E=1.',
    () async {
      final adminClient = clientFor(admin.id);
      final techClient = clientFor(technician.id);
      final users = UserRepositoryImpl(client: adminClient, guard: guard);
      final openWorkBefore = _value(await users.getById(technician.id))
          .activeTaskCount;
      final inventory = InventoryRepositoryImpl(
        client: adminClient,
        guard: guard,
      );
      final stockBefore = _value(await inventory.getItemById(material))
          .quantityAvailable;

      workOrderId = _value(
        await WorkOrderRepositoryImpl(
          client: adminClient,
          guard: guard,
        ).assignFromReport(
          reportId: reportId,
          personnelId: technician.id,
          actor: admin,
        ),
      );
      expect(
        _value(await users.getById(technician.id)).activeTaskCount,
        openWorkBefore + 1,
      );

      // The technician starts, uses a material, and files the report.
      final techWorkOrders = WorkOrderRepositoryImpl(
        client: techClient,
        guard: guard,
      );
      _value(
        await techWorkOrders.setStatus(
          workOrderId,
          WorkOrderStatus.inProgress,
          actor: technician,
        ),
      );
      _value(
        await MaterialUsageRepositoryImpl(
          client: techClient,
          guard: guard,
        ).record(
          workOrderId: workOrderId,
          inventoryItemId: material,
          quantity: 1,
          actor: technician,
        ),
      );
      final accomplishments = AccomplishmentReportRepositoryImpl(
        client: techClient,
        guard: guard,
      );
      final accomplishmentId = accomplishments.newReportId();
      final after = _value(
        await SupabaseStorageService(
          client: techClient,
          currentUid: () => technician.id,
          guard: guard,
        ).uploadFile(
          path: StoragePaths.accomplishmentPhoto(accomplishmentId, 'after.png'),
          bytes: _photo,
        ),
      );
      final item = _value(await inventory.getItemById(material));
      _value(
        await accomplishments.submit(
          reportId: accomplishmentId,
          workOrderId: workOrderId,
          completionNotes: 'Replaced the socket and tested it.',
          photoUrls: [after],
          materialsUsed: [
            MaterialUsage(
              inventoryItemId: material,
              itemName: item.name,
              quantityUsed: 1,
              unitOfMeasurement: item.unitOfMeasurement,
            ),
          ],
          actor: technician,
        ),
      );

      // The material came off the stock, through the ledger.
      expect(
        _value(await inventory.getItemById(material)).quantityAvailable,
        stockBefore - 1,
      );
      final ledger = _value(
        await inventory.getTransactionsForWorkOrder(workOrderId),
      );
      expect(ledger.single.accomplishmentReportId, accomplishmentId);

      // Signed off: completed, and the work no longer counts against them.
      _value(
        await AccomplishmentReportRepositoryImpl(
          client: adminClient,
          guard: guard,
        ).review(reportId: accomplishmentId, approve: true, actor: admin),
      );
      final workOrder = _value(
        await WorkOrderRepositoryImpl(
          client: adminClient,
          guard: guard,
        ).getById(workOrderId),
      );
      expect(workOrder.status, WorkOrderStatus.completed);
      expect(
        _value(await users.getById(technician.id)).activeTaskCount,
        openWorkBefore,
      );

      // The requestor rates the work, which closes the report.
      final requestorClient = clientFor(requestor.id);
      _value(
        await FeedbackRepositoryImpl(
          client: requestorClient,
          guard: guard,
        ).rate(
          reportId: reportId,
          rater: requestor,
          responseTime: 5,
          serviceQuality: 4,
          overallSatisfaction: 5,
          comments: 'Quick and tidy.',
        ),
      );
      expect(
        _value(
          await DamageReportRepositoryImpl(
            client: requestorClient,
            guard: guard,
          ).getById(reportId),
        ).status,
        ReportStatus.closed,
      );

      final trail = _value(
        await AuditLogRepositoryImpl(
          client: adminClient,
          guard: guard,
        ).getForEntity(entityType: 'work_orders', entityId: workOrderId),
      ).map((entry) => entry.description);
      expect(
        trail,
        containsAll([
          'Work order created from report $reportId',
          'Status changed from Pending to In Progress',
          'Status changed from In Progress to For Review',
          'Status changed from For Review to Completed',
        ]),
      );
    },
  );
}
