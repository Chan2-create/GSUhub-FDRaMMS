import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/inventory_transaction_type.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/enums/personnel_availability.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/task_status.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/features/accomplishment/data/models/accomplishment_report.dart';
import 'package:gsuhub/features/accomplishment/data/models/material_usage.dart';
import 'package:gsuhub/features/audit/data/models/audit_log_entry.dart';
import 'package:gsuhub/features/classification/data/models/classification_rules_config.dart';
import 'package:gsuhub/features/classification/data/models/duplicate_detection_config.dart';
import 'package:gsuhub/features/classification/data/models/prioritization_config.dart';
import 'package:gsuhub/features/facilities/data/models/asset.dart';
import 'package:gsuhub/features/facilities/data/models/facility.dart';
import 'package:gsuhub/features/feedback/data/models/service_feedback.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_item.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_transaction.dart';
import 'package:gsuhub/features/notifications/data/models/app_notification.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/tasks/data/models/maintenance_task.dart';
import 'package:gsuhub/features/tools/data/models/tool.dart';
import 'package:gsuhub/features/tools/data/models/tool_loan.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

import '../../support/firestore_round_trip.dart';

/// `toFirestore()` -> Firestore -> `fromFirestore()` -> equal object, for
/// every model.
///
/// These catch the failure mode that matters most in a schema layer: a
/// field written under one key and read back under another, or written as
/// one type and read as another. Both compile fine, and both silently lose
/// data in production.
void main() {
  final createdAt = DateTime.utc(2026, 3, 2, 8, 30);
  final updatedAt = DateTime.utc(2026, 3, 2, 9, 15);

  group('round-trip serialization', () {
    test('AppUser', () async {
      final original = AppUser(
        id: 'user-1',
        fullName: 'Juan Dela Cruz',
        email: 'juan.dc@dorsu.edu.ph',
        role: UserRole.maintenancePersonnel,
        accountStatus: AccountStatus.active,
        department: 'General Services Unit',
        contactNumber: '09171234567',
        specialization: DamageCategory.electrical,
        availability: PersonnelAvailability.available,
        activeTaskCount: 3,
        fcmToken: 'token-abc',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.users,
        original.id,
        original.toFirestore(),
      );

      expect(AppUser.fromFirestore(doc), original);
    });

    test('Facility', () async {
      final original = Facility(
        id: 'fac-1',
        name: 'Engineering Building',
        buildingName: 'Engineering Building',
        roomIdentifier: 'Room 101',
        locationDescription: '1st Floor, East Wing',
        coordinates: const GeoPoint(7.2048, 126.5354),
        qrCode: 'FAC-ENG-101',
        isActive: true,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.facilities,
        original.id,
        original.toFirestore(),
      );

      final restored = Facility.fromFirestore(doc);
      expect(restored, original);
      expect(restored.coordinates, const GeoPoint(7.2048, 126.5354));
    });

    test('Asset', () async {
      final original = Asset(
        id: 'asset-1',
        name: 'Split-Type Aircon Unit',
        qrCode: 'AST-AC-014',
        facilityId: 'fac-1',
        condition: ItemCondition.good,
        category: 'Air Conditioning Unit',
        serialNumber: 'SN-88421',
        acquiredAt: DateTime.utc(2024, 6),
        isActive: true,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.assets,
        original.id,
        original.toFirestore(),
      );

      expect(Asset.fromFirestore(doc), original);
    });

    test('DamageReport with every optional field populated', () async {
      final original = DamageReport(
        id: 'rep-1',
        reporterId: 'user-1',
        reporterName: 'Maria Santos',
        title: 'Broken Ceiling Fan',
        description: 'Ceiling fan in Room 204 wobbles badly and makes noise.',
        category: DamageCategory.electrical,
        classifiedAutomatically: true,
        facilityId: 'fac-1',
        facilityName: 'Engineering Building',
        locationDescription: 'Room 204',
        assetId: 'asset-9',
        coordinates: const GeoPoint(7.2048, 126.5354),
        photoUrls: const ['https://example.test/a.jpg'],
        requestorPriority: PriorityLevel.high,
        severityRating: 3,
        safetyRiskRating: 4,
        frequencyRating: 2,
        locationImportanceRating: 3,
        priorityScore: 3.2,
        recommendedPriority: PriorityLevel.high,
        officialPriority: PriorityLevel.critical,
        status: ReportStatus.assigned,
        workOrderId: 'wo-1',
        reviewedBy: 'admin-1',
        reviewedAt: updatedAt,
        submittedAt: createdAt,
        updatedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.damageReports,
        original.id,
        original.toFirestore(),
      );

      expect(DamageReport.fromFirestore(doc), original);
    });

    test('DamageReport with only required fields', () async {
      final original = DamageReport(
        id: 'rep-2',
        reporterId: 'user-2',
        reporterName: 'John Doe',
        title: 'Leaking pipe',
        description: 'Water pooling under the sink in the science lab.',
        requestorPriority: PriorityLevel.medium,
        status: ReportStatus.submitted,
        submittedAt: createdAt,
        updatedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.damageReports,
        original.id,
        original.toFirestore(),
      );
      final restored = DamageReport.fromFirestore(doc);

      expect(restored, original);
      expect(restored.category, isNull);
      expect(restored.officialPriority, isNull);
      expect(restored.photoUrls, isEmpty);
    });

    test('WorkOrder preserves its reportIds array', () async {
      final original = WorkOrder(
        id: 'wo-1',
        reportIds: const ['rep-1', 'rep-7'],
        title: 'Repair ceiling fan',
        description: 'Replace bearing and rebalance blades.',
        category: DamageCategory.electrical,
        priority: PriorityLevel.high,
        status: WorkOrderStatus.inProgress,
        assignedPersonnelIds: const ['user-1'],
        facilityId: 'fac-1',
        facilityName: 'Engineering Building',
        adminNotes: 'Prioritize before the 2 PM lab session.',
        scheduledFor: updatedAt,
        startedAt: updatedAt,
        createdBy: 'admin-1',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.workOrders,
        original.id,
        original.toFirestore(),
      );
      final restored = WorkOrder.fromFirestore(doc);

      expect(restored, original);
      expect(restored.reportIds, ['rep-1', 'rep-7']);
      expect(restored.isMergedFromDuplicates, isTrue);
    });

    test('MaintenanceTask', () async {
      final original = MaintenanceTask(
        id: 'task-1',
        workOrderId: 'wo-1',
        title: 'Replace AC filters',
        description: 'HM 101, 2nd floor.',
        assignedTo: 'user-1',
        status: TaskStatus.inProgress,
        dueDate: updatedAt,
        proofPhotoUrls: const ['https://example.test/proof.jpg'],
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.tasks,
        original.id,
        original.toFirestore(),
      );

      expect(MaintenanceTask.fromFirestore(doc), original);
    });

    test('AccomplishmentReport with embedded material usage', () async {
      final original = AccomplishmentReport(
        id: 'acc-1',
        workOrderId: 'wo-1',
        submittedBy: 'user-1',
        completionNotes: 'Replaced filter mesh and topped up coolant.',
        photoUrls: const ['https://example.test/done.jpg'],
        materialsUsed: [
          MaterialUsage(
            inventoryItemId: 'inv-1',
            itemName: 'Filter Mesh',
            quantityUsed: 2,
            unitOfMeasurement: 'units',
          ),
          MaterialUsage(
            inventoryItemId: 'inv-2',
            itemName: 'Coolant',
            quantityUsed: 1.5,
            unitOfMeasurement: 'L',
          ),
        ],
        submittedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.accomplishmentReports,
        original.id,
        original.toFirestore(),
      );
      final restored = AccomplishmentReport.fromFirestore(doc);

      expect(restored, original);
      expect(restored.materialsUsed, hasLength(2));
      expect(restored.materialsUsed.last.quantityUsed, 1.5);
      expect(restored.inventoryDeducted, isFalse);
    });

    test('InventoryItem', () async {
      final original = InventoryItem(
        id: 'inv-1',
        name: 'LED Bulbs (60W Eq)',
        category: 'Electrical',
        quantityAvailable: 452,
        unitOfMeasurement: 'units',
        storageLocation: 'GSU Store Room A',
        qrCode: 'INV-LED-60',
        minimumThreshold: 50,
        condition: ItemCondition.excellent,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.inventoryItems,
        original.id,
        original.toFirestore(),
      );
      final restored = InventoryItem.fromFirestore(doc);

      expect(restored, original);
      expect(restored.isLowStock, isFalse);
    });

    test('InventoryTransaction', () async {
      final original = InventoryTransaction(
        id: 'txn-1',
        inventoryItemId: 'inv-1',
        itemName: 'LED Bulbs (60W Eq)',
        type: InventoryTransactionType.consumption,
        quantity: 4,
        quantityBefore: 452,
        quantityAfter: 448,
        workOrderId: 'wo-1',
        accomplishmentReportId: 'acc-1',
        notes: 'Auto-deducted on accomplishment report submission.',
        performedBy: 'user-1',
        performedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.inventoryTransactions,
        original.id,
        original.toFirestore(),
      );

      expect(InventoryTransaction.fromFirestore(doc), original);
    });

    test('Tool', () async {
      final original = Tool(
        id: 'tool-1',
        toolCode: 'TL-0824',
        name: 'DeWalt Impact Driver 20V',
        status: ToolStatus.borrowed,
        condition: ItemCondition.excellent,
        category: 'Power Tools',
        storageLocation: 'GSU Tool Crib',
        currentHolderId: 'user-1',
        currentLoanId: 'loan-1',
        qrCode: 'TOOL-0824',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.tools,
        original.id,
        original.toFirestore(),
      );

      expect(Tool.fromFirestore(doc), original);
    });

    test('ToolLoan, open and closed', () async {
      final open = ToolLoan(
        id: 'loan-1',
        toolId: 'tool-1',
        toolName: 'DeWalt Impact Driver 20V',
        borrowedBy: 'user-1',
        workOrderId: 'wo-1',
        borrowedAt: createdAt,
        expectedReturnAt: updatedAt,
        conditionOnBorrow: ItemCondition.excellent,
      );

      final openDoc = await roundTrip(
        FirestorePaths.toolLoans,
        open.id,
        open.toFirestore(),
      );
      expect(ToolLoan.fromFirestore(openDoc), open);
      expect(open.isReturned, isFalse);

      final closed = open.copyWith(
        returnedAt: updatedAt,
        conditionOnReturn: ItemCondition.good,
      );
      final closedDoc = await roundTrip(
        FirestorePaths.toolLoans,
        closed.id,
        closed.toFirestore(),
      );
      final restoredClosed = ToolLoan.fromFirestore(closedDoc);

      expect(restoredClosed, closed);
      expect(restoredClosed.isReturned, isTrue);
      expect(restoredClosed.conditionDegraded, isTrue);
    });

    test('ServiceFeedback keeps three independent ratings', () async {
      final original = ServiceFeedback(
        id: 'fb-1',
        workOrderId: 'wo-1',
        reportId: 'rep-1',
        submittedBy: 'user-2',
        responseTimeRating: 2,
        serviceQualityRating: 5,
        overallSatisfactionRating: 4,
        comments: 'Slow to arrive but the repair itself was excellent.',
        submittedAt: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.feedback,
        original.id,
        original.toFirestore(),
      );
      final restored = ServiceFeedback.fromFirestore(doc);

      expect(restored, original);
      expect(restored.responseTimeRating, 2);
      expect(restored.serviceQualityRating, 5);
      expect(restored.overallSatisfactionRating, 4);
    });

    test('AppNotification', () async {
      final original = AppNotification(
        id: 'notif-1',
        recipientId: 'user-2',
        type: NotificationType.workOrderAssigned,
        title: 'Work order assigned',
        body: 'You have been assigned WO-2024-0905.',
        relatedEntityType: FirestorePaths.workOrders,
        relatedEntityId: 'wo-1',
        isRead: true,
        readAt: updatedAt,
        createdAt: createdAt,
      );

      final doc = await roundTrip(
        FirestorePaths.notifications,
        original.id,
        original.toFirestore(),
      );

      expect(AppNotification.fromFirestore(doc), original);
    });

    test('AuditLogEntry', () async {
      final original = AuditLogEntry(
        id: 'audit-1',
        actorId: 'admin-1',
        actorName: 'GSU Administrator',
        action: AuditAction.statusChanged,
        entityType: FirestorePaths.damageReports,
        entityId: 'rep-1',
        description: 'Official priority changed from High to Critical',
        changes: const {'officialPriority': 'critical'},
        timestamp: updatedAt,
      );

      final doc = await roundTrip(
        FirestorePaths.auditLogs,
        original.id,
        original.toFirestore(),
      );

      expect(AuditLogEntry.fromFirestore(doc), original);
    });

    test('PrioritizationConfig keeps both weight schemes intact', () async {
      final original = PrioritizationConfig.manuscriptDefaults(
        updatedAt: updatedAt,
        updatedBy: 'admin-1',
      );

      final doc = await roundTrip(
        FirestorePaths.config,
        'prioritization',
        original.toFirestore(),
      );
      final restored = PrioritizationConfig.fromFirestore(doc);

      expect(restored, original);
      // Both conflicting schemes survive the round trip — neither is
      // silently normalized away.
      expect(restored.integerWeights[PrioritizationCriterion.safetyRisk], 4);
      expect(restored.decimalWeights[PrioritizationCriterion.safetyRisk], 0.30);
    });

    test('ClassificationRulesConfig', () async {
      final original = ClassificationRulesConfig.seededFromManuscript(
        updatedAt: updatedAt,
        updatedBy: 'admin-1',
      );

      final doc = await roundTrip(
        FirestorePaths.config,
        'classification_rules',
        original.toFirestore(),
      );
      final restored = ClassificationRulesConfig.fromFirestore(doc);

      expect(restored, original);
      expect(
        restored.keywordsByCategory[DamageCategory.electrical],
        contains('exposed wire'),
      );
      expect(
        restored.keywordsByCategory[DamageCategory.generalMaintenance],
        isEmpty,
      );
    });

    test('DuplicateDetectionConfig', () async {
      final original = DuplicateDetectionConfig.defaults(
        updatedAt: updatedAt,
        updatedBy: 'admin-1',
      );

      final doc = await roundTrip(
        FirestorePaths.config,
        'duplicate_detection',
        original.toFirestore(),
      );
      final restored = DuplicateDetectionConfig.fromFirestore(doc);

      expect(restored, original);
      expect(restored.timeWindow, const Duration(hours: 72));
    });
  });
}
