import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/inventory_transaction_type.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/exceptions.dart';
import 'package:gsuhub/features/accomplishment/data/models/material_usage.dart';
import 'package:gsuhub/features/classification/data/models/duplicate_detection_config.dart';
import 'package:gsuhub/features/classification/data/models/prioritization_config.dart';
import 'package:gsuhub/features/feedback/data/models/service_feedback.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_item.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_transaction.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/tools/data/models/tool.dart';
import 'package:gsuhub/features/tools/data/models/tool_loan.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

import '../../support/firestore_round_trip.dart';

/// Validation on fields where the manuscript states a constraint, plus the
/// structural invariants the schema notes require.
void main() {
  final now = DateTime.utc(2026, 3, 2, 10);

  DamageReport buildReport({
    String description = 'A valid description of the damage.',
    int? severityRating,
    double? priorityScore,
  }) => DamageReport(
    id: 'rep-1',
    reporterId: 'user-1',
    reporterName: 'Maria Santos',
    title: 'Broken fan',
    description: description,
    requestorPriority: PriorityLevel.medium,
    status: ReportStatus.submitted,
    severityRating: severityRating,
    priorityScore: priorityScore,
    submittedAt: now,
    updatedAt: now,
  );

  group('DamageReport validation', () {
    test('rejects a blank description (manuscript §3.4 Reporting Policy)', () {
      expect(
        () => buildReport(description: '   '),
        throwsA(isA<ValidationException>()),
      );
    });

    test('accepts criterion ratings within the 1-4 scale', () {
      expect(buildReport(severityRating: 1).severityRating, 1);
      expect(buildReport(severityRating: 4).severityRating, 4);
    });

    test('rejects criterion ratings outside the 1-4 scale (Table 3.4)', () {
      expect(
        () => buildReport(severityRating: 0),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => buildReport(severityRating: 5),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a priority score outside 1.00-4.00 (Table 3.5)', () {
      expect(
        () => buildReport(priorityScore: 0.99),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => buildReport(priorityScore: 4.01),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rating fields are nullable — population path is unresolved', () {
      final report = buildReport();
      expect(report.severityRating, isNull);
      expect(report.safetyRiskRating, isNull);
      expect(report.frequencyRating, isNull);
      expect(report.locationImportanceRating, isNull);
    });

    test('effectivePriority prefers official, then recommended, then '
        'requestor', () {
      final base = buildReport();
      expect(base.effectivePriority, PriorityLevel.medium);

      final recommended = base.copyWith(
        recommendedPriority: PriorityLevel.high,
      );
      expect(recommended.effectivePriority, PriorityLevel.high);

      final official = recommended.copyWith(
        officialPriority: PriorityLevel.critical,
      );
      expect(official.effectivePriority, PriorityLevel.critical);
    });

    test('isDuplicate reflects the duplicateOf pointer', () {
      expect(buildReport().isDuplicate, isFalse);
      expect(buildReport().copyWith(duplicateOf: 'rep-9').isDuplicate, isTrue);
    });
  });

  group('WorkOrder validation', () {
    test('rejects a work order with no originating report', () {
      expect(
        () => WorkOrder(
          id: 'wo-1',
          reportIds: const [],
          title: 'Orphan',
          description: 'No source report',
          category: DamageCategory.electrical,
          priority: PriorityLevel.low,
          status: WorkOrderStatus.pending,
          createdBy: 'admin-1',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ServiceFeedback validation', () {
    ServiceFeedback build({
      int responseTime = 4,
      int quality = 4,
      int overall = 4,
    }) => ServiceFeedback(
      id: 'fb-1',
      workOrderId: 'wo-1',
      reportId: 'rep-1',
      submittedBy: 'user-2',
      responseTimeRating: responseTime,
      serviceQualityRating: quality,
      overallSatisfactionRating: overall,
      submittedAt: now,
    );

    test('accepts each rating across the full 1-5 range', () {
      expect(build(responseTime: 1).responseTimeRating, 1);
      expect(build(quality: 5).serviceQualityRating, 5);
      expect(build(overall: 3).overallSatisfactionRating, 3);
    });

    test('rejects out-of-range ratings', () {
      expect(() => build(responseTime: 0), throwsA(isA<ValidationException>()));
      expect(() => build(quality: 6), throwsA(isA<ValidationException>()));
      expect(() => build(overall: -1), throwsA(isA<ValidationException>()));
    });

    test('keeps the three ratings independent (manuscript §1.5)', () {
      final feedback = build(responseTime: 1, quality: 5, overall: 3);
      expect(feedback.responseTimeRating, 1);
      expect(feedback.serviceQualityRating, 5);
      expect(feedback.overallSatisfactionRating, 3);
    });
  });

  group('InventoryItem validation', () {
    InventoryItem build({required double quantity, double threshold = 5}) =>
        InventoryItem(
          id: 'inv-1',
          name: 'LED Bulb',
          category: 'Electrical',
          quantityAvailable: quantity,
          unitOfMeasurement: 'units',
          storageLocation: 'Store A',
          qrCode: 'INV-1',
          minimumThreshold: threshold,
          createdAt: now,
          updatedAt: now,
        );

    test('rejects negative stock', () {
      expect(() => build(quantity: -1), throwsA(isA<ValidationException>()));
    });

    test('isLowStock fires at and below the threshold', () {
      expect(build(quantity: 6).isLowStock, isFalse);
      expect(build(quantity: 5).isLowStock, isTrue);
      expect(build(quantity: 1).isLowStock, isTrue);
    });
  });

  group('InventoryTransaction — append-only ledger', () {
    InventoryTransaction build({double quantity = 5}) => InventoryTransaction(
      id: 'txn-1',
      inventoryItemId: 'inv-1',
      itemName: 'LED Bulb',
      type: InventoryTransactionType.consumption,
      quantity: quantity,
      quantityBefore: 10,
      quantityAfter: 5,
      performedBy: 'user-1',
      performedAt: now,
    );

    test('rejects a non-positive quantity — direction comes from the type', () {
      expect(() => build(quantity: 0), throwsArgumentError);
      expect(() => build(quantity: -5), throwsArgumentError);
    });

    test('deduction types are distinguishable from additions', () {
      expect(InventoryTransactionType.consumption.isDeduction, isTrue);
      expect(InventoryTransactionType.issuance.isDeduction, isTrue);
      expect(InventoryTransactionType.replenishment.isDeduction, isFalse);
      expect(InventoryTransactionType.returned.isDeduction, isFalse);
    });

    test('records the balance either side of the movement', () {
      final txn = build();
      expect(txn.quantityBefore, 10);
      expect(txn.quantityAfter, 5);
    });
  });

  group('MaterialUsage validation', () {
    test('rejects a non-positive quantity', () {
      expect(
        () => MaterialUsage(
          inventoryItemId: 'inv-1',
          itemName: 'Coolant',
          quantityUsed: 0,
          unitOfMeasurement: 'L',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Tool and ToolLoan accountability invariants', () {
    test('a borrowed tool must name its holder (manuscript §1.5)', () {
      expect(
        () => Tool(
          id: 'tool-1',
          toolCode: 'TL-1',
          name: 'Drill',
          status: ToolStatus.borrowed,
          condition: ItemCondition.good,
          qrCode: 'TOOL-1',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('a returned tool must record its condition on return', () {
      expect(
        () => ToolLoan(
          id: 'loan-1',
          toolId: 'tool-1',
          toolName: 'Drill',
          borrowedBy: 'user-1',
          borrowedAt: now,
          conditionOnBorrow: ItemCondition.good,
          returnedAt: now.add(const Duration(hours: 2)),
        ),
        throwsArgumentError,
      );
    });

    test('a tool cannot be returned before it was borrowed', () {
      expect(
        () => ToolLoan(
          id: 'loan-1',
          toolId: 'tool-1',
          toolName: 'Drill',
          borrowedBy: 'user-1',
          borrowedAt: now,
          conditionOnBorrow: ItemCondition.good,
          returnedAt: now.subtract(const Duration(hours: 1)),
          conditionOnReturn: ItemCondition.good,
        ),
        throwsArgumentError,
      );
    });

    test('isOverdue is evaluated against a supplied clock', () {
      final loan = ToolLoan(
        id: 'loan-1',
        toolId: 'tool-1',
        toolName: 'Drill',
        borrowedBy: 'user-1',
        borrowedAt: now,
        expectedReturnAt: now.add(const Duration(days: 1)),
        conditionOnBorrow: ItemCondition.good,
      );

      expect(loan.isOverdue(now.add(const Duration(hours: 12))), isFalse);
      expect(loan.isOverdue(now.add(const Duration(days: 2))), isTrue);
    });
  });

  group('AppUser validation', () {
    test('rejects a negative denormalized task count', () {
      expect(
        () => AppUser(
          id: 'user-1',
          fullName: 'Test User',
          email: 'test@dorsu.edu.ph',
          role: UserRole.maintenancePersonnel,
          accountStatus: AccountStatus.active,
          activeTaskCount: -1,
          createdAt: now,
          updatedAt: now,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a blank name or email', () {
      expect(
        () => AppUser(
          id: 'user-1',
          fullName: '  ',
          email: 'test@dorsu.edu.ph',
          role: UserRole.requestor,
          accountStatus: AccountStatus.active,
          createdAt: now,
          updatedAt: now,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('PrioritizationConfig — the unresolved weight conflict', () {
    test('holds both schemes simultaneously', () {
      final config = PrioritizationConfig.manuscriptDefaults(
        updatedAt: now,
        updatedBy: 'admin-1',
      );

      expect(config.integerWeights[PrioritizationCriterion.safetyRisk], 4);
      expect(config.decimalWeights[PrioritizationCriterion.safetyRisk], 0.30);
    });

    test('the two schemes disagree on which criterion ranks highest', () {
      final config = PrioritizationConfig.manuscriptDefaults(
        updatedAt: now,
        updatedBy: 'admin-1',
      );

      String highestOf(Map<PrioritizationCriterion, double> weights) {
        final sorted = weights.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return sorted.first.key.id;
      }

      expect(highestOf(config.integerWeights), 'safetyRisk');
      expect(highestOf(config.decimalWeights), 'severity');
    });

    test('the decimal scheme is normalized, the integer scheme is not', () {
      final decimal = PrioritizationConfig.manuscriptDefaults(
        updatedAt: now,
        updatedBy: 'admin-1',
      );
      expect(decimal.activeWeightsAreNormalized, isTrue);

      final integer = decimal.copyWith(
        activeScheme: PrioritizationScheme.integerWeights,
      );
      expect(integer.activeWeightsAreNormalized, isFalse);
    });

    test('activeWeights follows the scheme discriminator', () {
      final config = PrioritizationConfig.manuscriptDefaults(
        updatedAt: now,
        updatedBy: 'admin-1',
        activeScheme: PrioritizationScheme.integerWeights,
      );
      expect(config.activeWeights, config.integerWeights);
    });

    test('rejects an inverted rating scale', () {
      expect(
        () => PrioritizationConfig(
          activeScheme: PrioritizationScheme.decimalWeights,
          integerWeights: const {
            PrioritizationCriterion.severity: 3,
            PrioritizationCriterion.safetyRisk: 4,
            PrioritizationCriterion.frequency: 2,
            PrioritizationCriterion.locationImportance: 3,
          },
          decimalWeights: const {
            PrioritizationCriterion.severity: 0.40,
            PrioritizationCriterion.safetyRisk: 0.30,
            PrioritizationCriterion.frequency: 0.20,
            PrioritizationCriterion.locationImportance: 0.10,
          },
          thresholds: const {
            PriorityLevel.critical: 3.5,
            PriorityLevel.high: 2.5,
            PriorityLevel.medium: 1.5,
            PriorityLevel.low: 1.0,
          },
          minRating: 4,
          maxRating: 1,
          updatedAt: now,
          updatedBy: 'admin-1',
        ),
        throwsArgumentError,
      );
    });
  });

  group('DuplicateDetectionConfig validation', () {
    test('rejects a similarity threshold outside 0.0-1.0', () {
      expect(
        () => DuplicateDetectionConfig(
          enabled: true,
          descriptionSimilarityThreshold: 1.5,
          timeWindowHours: 24,
          updatedAt: now,
          updatedBy: 'admin-1',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a non-positive time window', () {
      expect(
        () => DuplicateDetectionConfig(
          enabled: true,
          descriptionSimilarityThreshold: 0.8,
          timeWindowHours: 0,
          updatedAt: now,
          updatedBy: 'admin-1',
        ),
        throwsArgumentError,
      );
    });
  });

  group('FirestoreConverters error reporting', () {
    test('names the field when a required one is missing', () async {
      final doc = await roundTrip('inventory_items', 'inv-1', {
        'name': 'LED Bulb',
      });

      expect(
        () => InventoryItem.fromFirestore(doc),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('category'),
          ),
        ),
      );
    });

    test('names the field when an enum value is unrecognized', () async {
      final doc = await roundTrip('tools', 'tool-1', {
        'toolCode': 'TL-1',
        'name': 'Drill',
        'status': 'teleported',
        'condition': 'good',
        'qrCode': 'TOOL-1',
      });

      expect(
        () => Tool.fromFirestore(doc),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('status'),
          ),
        ),
      );
    });
  });
}
