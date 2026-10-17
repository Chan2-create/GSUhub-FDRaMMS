import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/personnel_availability.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/task_status.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/location_service.dart';
import 'package:gsuhub/core/services/supabase/supabase_call_guard.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/accomplishment/data/models/material_usage.dart';
import 'package:gsuhub/features/accomplishment/data/repositories/accomplishment_report_repository_impl.dart';
import 'package:gsuhub/features/accomplishment/data/repositories/material_usage_repository_impl.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/classification/data/models/classification_rules_config.dart';
import 'package:gsuhub/features/classification/data/models/duplicate_detection_config.dart';
import 'package:gsuhub/features/classification/data/models/prioritization_config.dart';
import 'package:gsuhub/features/classification/data/repositories/config_repository_impl.dart';
import 'package:gsuhub/features/facilities/data/models/facility_draft.dart';
import 'package:gsuhub/features/facilities/data/repositories/facility_repository_impl.dart';
import 'package:gsuhub/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_item_draft.dart';
import 'package:gsuhub/features/inventory/data/models/material_line.dart';
import 'package:gsuhub/features/inventory/data/repositories/inventory_repository_impl.dart';
import 'package:gsuhub/features/inventory/data/repositories/material_allocation_repository_impl.dart';
import 'package:gsuhub/features/inventory/data/repositories/material_request_repository_impl.dart';
import 'package:gsuhub/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:gsuhub/features/reporting/data/models/report_assessment.dart';
import 'package:gsuhub/features/reporting/data/models/report_submission.dart';
import 'package:gsuhub/features/reporting/data/repositories/damage_report_repository_impl.dart';
import 'package:gsuhub/features/tasks/data/repositories/task_repository_impl.dart';
import 'package:gsuhub/features/tools/data/models/tool_draft.dart';
import 'package:gsuhub/features/tools/data/repositories/tool_repository_impl.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/user_management/data/repositories/user_repository_impl.dart';
import 'package:gsuhub/features/work_orders/data/repositories/work_order_repository_impl.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';

import '../../support/test_app_config.dart';

/// The contract between the Supabase repositories and the database: every
/// function a repository calls exists among the migrations' `public.*`
/// functions, takes every parameter it is sent, and is sent every
/// parameter it has no default for. A misspelt key would otherwise
/// surface only against a running stack, as PostgREST's "could not find
/// the function".
typedef _Signature = ({Set<String> all, Set<String> required});

Map<String, _Signature> _sqlSignatures() {
  final signatures = <String, _Signature>{};
  final declaration = RegExp(
    r'create or replace function public\.(\w+)\s*\(([^)]*)\)',
    caseSensitive: false,
  );
  final files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sql'));
  for (final file in files) {
    for (final match in declaration.allMatches(file.readAsStringSync())) {
      final all = <String>{};
      final required = <String>{};
      for (final parameter in match.group(2)!.split(',')) {
        final text = parameter.trim();
        if (text.isEmpty) continue;
        final name = text.split(RegExp(r'\s+')).first;
        all.add(name);
        if (!text.toLowerCase().contains(' default ')) required.add(name);
      }
      signatures[match.group(1)!] = (all: all, required: required);
    }
  }
  return signatures;
}

void main() {
  final signatures = _sqlSignatures();
  final calls = <(String, Map<String, dynamic>)>[];
  late SupabaseClient client;
  late SupabaseCallGuard guard;

  setUp(() {
    calls.clear();
    client = SupabaseClient(
      'http://localhost:54321',
      'anon-key',
      accessToken: () async => 'token',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.startsWith('/rest/v1/rpc/')) {
          final function = path.substring('/rest/v1/rpc/'.length);
          final body = request.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(request.body) as Map<String, dynamic>;
          calls.add((function, body));
          final returnsId =
              function.startsWith('create_') && function != 'create_account' ||
              function == 'assign_work_order' ||
              function == 'add_task';
          return http.Response(
            returnsId ? '"new-id"' : 'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    guard = SupabaseCallGuard(testAppConfig());
    addTearDown(client.dispose);
  });

  const actor = AuditActor(id: 'u-admin', name: 'Ramon Dela Cruz');
  final now = DateTime.utc(2026, 10, 16, 8);
  final user = AppUser(
    id: 'u-1',
    fullName: 'Marcus Wright',
    email: 'tech@test.ph',
    role: UserRole.maintenancePersonnel,
    accountStatus: AccountStatus.active,
    specialization: DamageCategory.electrical,
    availability: PersonnelAvailability.available,
    createdAt: now,
    updatedAt: now,
  );

  /// Every write each repository makes, called once.
  Future<void> exerciseEveryWrite() async {
    final users = UserRepositoryImpl(client: client, guard: guard);
    await users.createSelfRegistration(user);
    await users.createAccount(user: user, actor: actor);
    await users.updateAccount(updated: user, actor: actor);
    await users.setAccountStatus('u-1', AccountStatus.inactive, actor: actor);
    await users.setFcmToken('u-1', 'token');

    final facilities = FacilityRepositoryImpl(client: client, guard: guard);
    const room = FacilityDraft(
      buildingName: 'Science Building',
      roomIdentifier: 'Lab 2',
      latitude: 7.1,
      longitude: 126.5,
    );
    const asset = AssetDraft(
      name: 'Aircon Unit',
      facilityId: 'f-1',
      condition: ItemCondition.good,
    );
    await facilities.createFacility(draft: room, actor: actor);
    await facilities.updateFacility(
      facilityId: 'f-1',
      draft: room,
      actor: actor,
    );
    await facilities.setFacilityActive(
      facilityId: 'f-1',
      active: false,
      actor: actor,
    );
    await facilities.createAsset(draft: asset, actor: actor);
    await facilities.updateAsset(assetId: 'a-1', draft: asset, actor: actor);
    await facilities.setAssetActive(
      assetId: 'a-1',
      active: false,
      actor: actor,
    );

    final reports = DamageReportRepositoryImpl(client: client, guard: guard);
    await reports.submit(
      reportId: reports.newReportId(),
      submission: const ReportSubmission(
        reporter: AuditActor(id: 'u-req', name: 'Maria Santos'),
        title: 'Broken window',
        description: 'Glass cracked.',
        requestorPriority: PriorityLevel.high,
        requestorCategory: DamageCategory.structural,
        classifiedCategory: DamageCategory.structural,
        facilityId: 'f-1',
        facilityName: 'Engineering Building',
        coordinates: GeoCoordinates(latitude: 7.1, longitude: 126.5),
        photoUrls: ['https://photos.test/1.jpg'],
      ),
    );
    await reports.recordAssessment(
      reportId: 'r-1',
      assessment: ReportAssessment(
        category: DamageCategory.electrical,
        classifiedAutomatically: false,
        severityRating: 3,
        safetyRiskRating: 2,
        frequencyRating: 2,
        locationImportanceRating: 2,
        priorityScore: 2.4,
        recommendedPriority: PriorityLevel.medium,
        officialPriority: PriorityLevel.high,
      ),
      actor: actor,
    );
    await reports.transitionStatus(
      reportId: 'r-1',
      to: ReportStatus.rejected,
      actor: actor,
      reason: 'Not ours.',
    );
    await reports.mergeDuplicates(
      parentReportId: 'r-1',
      duplicateReportIds: ['r-2'],
      actor: actor,
    );
    await reports.keepSeparate(
      reportId: 'r-1',
      otherReportId: 'r-2',
      actor: actor,
    );

    final workOrders = WorkOrderRepositoryImpl(client: client, guard: guard);
    await workOrders.assignFromReport(
      reportId: 'r-1',
      personnelId: 'u-1',
      actor: actor,
      scheduledFor: now,
    );
    await workOrders.setStatus('w-1', WorkOrderStatus.inProgress, actor: actor);
    await workOrders.updateAdminNotes(
      workOrderId: 'w-1',
      notes: 'Bring a ladder.',
      actor: actor,
    );

    await FeedbackRepositoryImpl(client: client, guard: guard).rate(
      reportId: 'r-1',
      rater: const AuditActor(id: 'u-req', name: 'Maria Santos'),
      responseTime: 4,
      serviceQuality: 5,
      overallSatisfaction: 3,
      comments: 'Quick.',
    );

    final notifications = NotificationRepositoryImpl(
      client: client,
      guard: guard,
    );
    await notifications.markAsRead('n-1');
    await notifications.markAllAsRead('u-1');

    final config = ConfigRepositoryImpl(client: client, guard: guard);
    await config.updateClassificationRules(
      ClassificationRulesConfig.seededFromManuscript(
        updatedAt: now,
        updatedBy: 'u-admin',
      ),
    );
    await config.updatePrioritization(
      PrioritizationConfig.manuscriptDefaults(
        updatedAt: now,
        updatedBy: 'u-admin',
      ),
    );
    await config.updateDuplicateDetection(
      DuplicateDetectionConfig.defaults(updatedAt: now, updatedBy: 'u-admin'),
    );

    // Objective 1, M4.
    final tasks = TaskRepositoryImpl(client: client, guard: guard);
    await tasks.addTask(
      workOrderId: 'w-1',
      title: 'Check the valves',
      actor: actor,
      description: 'Under the sink',
      dueDate: now,
    );
    await tasks.deleteTask(taskId: 't-1', actor: actor);
    await tasks.setStatus(
      taskId: 't-1',
      status: TaskStatus.completed,
      actor: actor,
    );
    await tasks.addProofPhotos(
      taskId: 't-1',
      photoUrls: ['tasks/u-1/t-1/proof.jpg'],
      actor: actor,
    );

    final accomplishments = AccomplishmentReportRepositoryImpl(
      client: client,
      guard: guard,
    );
    await accomplishments.submit(
      reportId: accomplishments.newReportId(),
      workOrderId: 'w-1',
      completionNotes: 'Replaced the ballast.',
      photoUrls: ['accomplishment_reports/u-1/ac-1/after.jpg'],
      materialsUsed: [
        MaterialUsage(
          inventoryItemId: 'i-1',
          itemName: 'LED Bulbs',
          quantityUsed: 2,
          unitOfMeasurement: 'units',
        ),
      ],
      actor: actor,
    );
    await accomplishments.review(
      reportId: 'ac-1',
      approve: false,
      actor: actor,
      note: 'The cover still moves.',
    );

    final used = MaterialUsageRepositoryImpl(client: client, guard: guard);
    await used.record(
      workOrderId: 'w-1',
      inventoryItemId: 'i-1',
      quantity: 2,
      actor: actor,
    );
    await used.remove(workOrderId: 'w-1', inventoryItemId: 'i-1');

    final allocations = MaterialAllocationRepositoryImpl(
      client: client,
      guard: guard,
    );
    await allocations.allocate(
      workOrderId: 'w-1',
      inventoryItemId: 'i-1',
      quantity: 4,
      actor: actor,
    );
    await allocations.remove(
      workOrderId: 'w-1',
      inventoryItemId: 'i-1',
      actor: actor,
    );

    final requests = MaterialRequestRepositoryImpl(
      client: client,
      guard: guard,
    );
    await requests.submit(
      requestId: requests.newRequestId(),
      workOrderId: 'w-1',
      items: [
        MaterialLine(
          inventoryItemId: 'i-1',
          itemName: 'LED Bulbs',
          quantity: 2,
          unitOfMeasurement: 'units',
        ),
      ],
      actor: actor,
      note: 'For the hallway',
    );
    await requests.approve(requestId: 'm-1', actor: actor, note: 'At noon');
    await requests.decline(requestId: 'm-2', actor: actor, note: 'No budget');

    final inventory = InventoryRepositoryImpl(client: client, guard: guard);
    const material = InventoryItemDraft(
      name: 'Wire',
      category: 'Electrical',
      unitOfMeasurement: 'rolls',
      storageLocation: 'Store A',
      qrCode: 'INV-WIRE',
      minimumThreshold: 2,
      unitCost: 3850,
    );
    await inventory.createItem(draft: material, openingStock: 34, actor: actor);
    await inventory.updateItemDetails(
      itemId: 'i-1',
      draft: material,
      actor: actor,
    );
    await inventory.recordDelivery(itemId: 'i-1', quantity: 5, actor: actor);
    await inventory.recordStockCount(
      itemId: 'i-1',
      countedQuantity: 22,
      actor: actor,
      reason: 'Three broken',
    );

    final tools = ToolRepositoryImpl(client: client, guard: guard);
    const tool = ToolDraft(
      toolCode: 'TL-0100',
      name: 'Cordless Drill',
      condition: ItemCondition.good,
      qrCode: 'TOOL-TL-0100',
    );
    await tools.createTool(draft: tool, actor: actor);
    await tools.updateToolDetails(toolId: 'tl-1', draft: tool, actor: actor);
    await tools.setToolStatus(
      toolId: 'tl-1',
      status: ToolStatus.inRepair,
      actor: actor,
    );
    await tools.borrowTool(
      toolId: 'tl-1',
      borrower: const AuditActor(id: 'u-1', name: 'Marcus Wright'),
      issuedBy: actor,
      workOrderId: 'w-1',
      expectedReturnAt: now,
    );
    await tools.returnTool(
      loanId: 'lo-1',
      conditionOnReturn: ItemCondition.poor,
      actor: actor,
      notes: 'A rung is cracked',
    );
  }

  test('the migrations declare the API functions', () {
    expect(signatures.length, greaterThanOrEqualTo(45));
  });

  test('every write calls a database function that exists, with the '
      'parameters it takes', () async {
    await exerciseEveryWrite();
    expect(calls, hasLength(47));
    for (final (function, params) in calls) {
      final signature = signatures[function];
      expect(
        signature,
        isNotNull,
        reason: 'no public.$function in the migrations',
      );
      expect(
        params.keys.toSet().difference(signature!.all),
        isEmpty,
        reason: 'public.$function takes no such parameter',
      );
      expect(
        signature.required.difference(params.keys.toSet()),
        isEmpty,
        reason: 'public.$function was not sent a parameter it requires',
      );
    }
  });

  test('every database function is called by the app', () async {
    await exerciseEveryWrite();
    expect(
      signatures.keys.toSet().difference({for (final (f, _) in calls) f}),
      isEmpty,
    );
  });

  test('the settings document goes without who saved it and when: the '
      'database stamps those', () async {
    await ConfigRepositoryImpl(
      client: client,
      guard: guard,
    ).updateClassificationRules(
      ClassificationRulesConfig.seededFromManuscript(
        updatedAt: now,
        updatedBy: 'u-admin',
      ),
    );
    final data = calls.single.$2['data'] as Map<String, dynamic>;
    expect(data.containsKey('updatedAt'), isFalse);
    expect(data.containsKey('updatedBy'), isFalse);
    expect(data['keywordsByCategory'], isA<Map<String, dynamic>>());
  });

  test(
    "a room's default code is made from the id it is created with",
    () async {
      final created = await FacilityRepositoryImpl(client: client, guard: guard)
          .createFacility(
            draft: const FacilityDraft(buildingName: 'Gym'),
            actor: actor,
          );
      final params = calls.single.$2;
      expect(
        params['qr_code'],
        FacilityDraft.defaultQrCode(params['id'] as String),
      );
      expect(created.fold((id) => id, (_) => null), 'new-id');
    },
  );

  test('a draft with a problem is refused before anything is sent', () async {
    final result = await FacilityRepositoryImpl(client: client, guard: guard)
        .createFacility(
          draft: const FacilityDraft(buildingName: ' '),
          actor: actor,
        );
    expect(
      result.fold((_) => null, (failure) => failure),
      isA<ValidationFailure>(),
    );
    expect(calls, isEmpty);
  });

  test("a database function's refusal reaches the app as written", () async {
    final refusing = SupabaseClient(
      'http://localhost:54321',
      'anon-key',
      accessToken: () async => 'token',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'code': 'PT409',
            'message':
                'You cannot change your own role. Ask another administrator.',
          }),
          409,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    addTearDown(refusing.dispose);
    final result = await UserRepositoryImpl(
      client: refusing,
      guard: guard,
    ).updateAccount(updated: user, actor: actor);
    expect(
      result.fold((_) => null, (failure) => failure),
      isA<ValidationFailure>().having(
        (f) => f.message,
        'message',
        'You cannot change your own role. Ask another administrator.',
      ),
    );
  });

  test(
    'the writes nothing calls refuse rather than write around the rules',
    () async {
      final users = UserRepositoryImpl(client: client, guard: guard);
      final results = <Result<Object?>>[
        await users.update(user),
        await users.create(user),
        await users.adjustActiveTaskCount('u-1', 1),
        await users.setAvailability('u-1', PersonnelAvailability.onLeave),
      ];
      for (final result in results) {
        expect(result.isFailure, isTrue);
      }
      expect(calls, isEmpty);
    },
  );
}
